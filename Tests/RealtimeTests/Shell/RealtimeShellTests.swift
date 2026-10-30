//
//  RealtimeShellTests.swift
//  RealtimeTests
//

import Clocks
import ConcurrencyExtras
import Foundation
import Helpers
import TestHelpers
import Testing

@testable import Realtime

/// The client as the shell around ``RealtimeCore``: it runs effects in order, drops stale timers
/// and frames, resumes waiters after the whole batch, and guards released clients and removed
/// channels.
@Suite(.timeLimit(.minutes(1)))
struct RealtimeShellTests {
  // MARK: Effect order

  @Test
  func effectsRunInCoreOrder() async throws {
    let host = await RealtimeTestHost()
    let a = host.client.channel("a")
    let b = host.client.channel("b")
    try await subscribe(a, on: host)
    try await subscribe(b, on: host)

    await host.client.setAuth("new-token")

    _ = try await host.receive { $0.event == ChannelEvent.accessToken && $0.topic == b.wireTopic }
    let frames = host.frames.filter { $0.topic != "phoenix" }
    #expect(
      frames.map(\.event) == [
        ChannelEvent.join, ChannelEvent.join, ChannelEvent.accessToken, ChannelEvent.accessToken,
      ])
    #expect(frames.map(\.topic) == [a.wireTopic, b.wireTopic, a.wireTopic, b.wireTopic])
    let refs = frames.compactMap { $0.ref.flatMap(Int.init) }
    #expect(refs == refs.sorted())
  }

  @Test
  func statusIsCurrentWhenSubscribeReturns() async throws {
    let host = await RealtimeTestHost()
    for index in 1...20 {
      let channel = host.client.channel("room-\(index)")
      try await subscribe(channel, on: host)
      // The resume comes before the status in the core's effects; the shell resumes the caller
      // only once the whole batch is applied.
      #expect(channel.status == .subscribed)
    }
  }

  @Test
  func joinSendsTheClientInfoHeaderAsItsVersion() async throws {
    let host = await RealtimeTestHost(
      options: RealtimeClientOptions(
        headers: ["X-Client-Info": "my-app/1.2"], handleAppLifecycle: false))
    let channel = host.client.channel("room")

    let join = try await subscribe(channel, on: host)

    #expect(join.payload["version"] == "my-app/1.2")
  }

  // MARK: Timers

  @Test
  func staleTimerFireIsIgnored() async throws {
    let host = await RealtimeTestHost(
      options: RealtimeClientOptions(requestTimeout: .seconds(10), handleAppLifecycle: false))
    let channel = host.client.channel("room")
    let subscription = Task { try await channel.subscribe() }
    let join = try await host.receive(event: ChannelEvent.join)
    let timeout = TimerID.joinTimeout(topic: "room", ref: join.ref ?? "")
    let first = await host.client.timers.task(for: timeout)

    // Replaces the join timeout, so its first deadline, at 10 s, is stale.
    await host.client.scheduleTimer(timeout, after: .seconds(20))
    await first?.value
    await host.clock.advance(by: .seconds(15))

    #expect(channel.status.isSame(as: .subscribing(attempt: 1)))
    #expect(host.frames.filter { $0.event == ChannelEvent.join }.count == 1)

    // The replacement still fires at its own deadline.
    await host.clock.advance(by: .seconds(5))
    await host.waitUntil {
      if case .resubscribing(1, _, _) = channel.status { true } else { false }
    }
    subscription.cancel()
    _ = await subscription.result
  }

  @Test
  func rejoinBackoffWaitsOneTwoFiveThenTenSeconds() async throws {
    let host = await RealtimeTestHost(
      options: RealtimeClientOptions(requestTimeout: .seconds(10), handleAppLifecycle: false))
    let channel = host.client.channel("room")
    let subscription = Task { try await channel.subscribe() }
    var waits: [Duration] = []

    for attempt in 1...5 {
      await host.waitUntil {
        host.frames.filter { $0.event == ChannelEvent.join }.count == attempt
      }
      await host.clock.advance(by: .seconds(10))
      await host.waitUntil {
        if case .resubscribing(attempt, _, _) = channel.status { true } else { false }
      }
      guard case .resubscribing(_, let retryIn, let error) = channel.status else {
        Issue.record("Expected a backoff after attempt \(attempt), got \(channel.status)")
        return
      }
      #expect(error.kind == .timeout)
      waits.append(retryIn)
      await host.clock.advance(by: retryIn)
    }

    #expect(waits == [.seconds(1), .seconds(2), .seconds(5), .seconds(10), .seconds(10)])
    subscription.cancel()
    _ = await subscription.result
  }

  // MARK: Cancellation

  @Test
  func cancelledSubscribeThrowsCancellationErrorAndLeaves() async throws {
    let host = await RealtimeTestHost()
    let channel = host.client.channel("room")
    let subscription = Task { try await channel.subscribe() }
    let join = try await host.receive(event: ChannelEvent.join)

    subscription.cancel()

    await #expect(throws: CancellationError.self) { try await subscription.value }
    let leave = try await host.receive(event: ChannelEvent.leave)
    #expect(leave.joinRef == join.ref)
    await host.waitUntil { channel.status == .unsubscribed }
    #expect(channel.status == .unsubscribed)
  }

  @Test
  func subscribeFromACancelledTaskSendsNothing() async throws {
    let host = await RealtimeTestHost()
    // Connected, so a join would go out at once.
    try await host.client.connect()
    let channel = host.client.channel("room")
    let cancelled = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      try await channel.subscribe()
    }

    await #expect(throws: CancellationError.self) { try await cancelled.value }
    // Frames leave in order, so once this join is in, any frame for "room" would be too.
    try await subscribe(host.client.channel("barrier"), on: host)

    #expect(host.frames.filter { $0.topic == channel.wireTopic }.isEmpty)
    #expect(channel.status == .unsubscribed)
  }

  // MARK: Socket

  @Test
  func framesFromOldSocketAreDropped() async throws {
    let host = await RealtimeTestHost()
    let channel = host.client.channel("room")
    let broadcasts = channel.broadcasts(event: "ping")
    try await subscribe(channel, on: host)
    let generation = await host.client.generation
    let frame = try RealtimeSerializer().encodeText(
      RealtimeMessage(
        joinRef: nil, ref: nil, topic: channel.wireTopic, event: ChannelEvent.broadcast,
        payload: ["event": "ping", "payload": ["n": 1]]))

    await host.client.receive(.frame(.text(frame)), generation: generation - 1)
    await host.client.receive(.closed(code: nil, reason: "old"), generation: generation - 1)
    await host.client.receive(.frame(.text(frame)), generation: generation)
    channel.sinks.finishAll()

    var received: [BroadcastMessage] = []
    for await message in broadcasts {
      received.append(message)
    }
    #expect(received.count == 1)
    #expect(host.client.status == .connected)
  }

  // MARK: Access token

  @Test
  func accessTokenCallbackTimeoutAppliesNil() async throws {
    let called = LockIsolated(false)
    let host = await RealtimeTestHost(
      options: RealtimeClientOptions(
        headers: ["Authorization": "Bearer stored"],
        requestTimeout: .seconds(5),
        accessToken: {
          called.setValue(true)
          // Never yields; the loop ends only when the call is cancelled.
          let (never, continuation) = AsyncStream<Never>.makeStream()
          for await _ in never {}
          continuation.finish()
          return "never"
        },
        handleAppLifecycle: false
      ))
    let channel = host.client.channel("room")
    let subscription = Task { try await channel.subscribe() }
    #expect(await waitUntil(timeout: 5) { called.value })

    await host.clock.advance(by: .seconds(5))

    let join = try await host.receive(event: ChannelEvent.join)
    #expect(join.payload["access_token"] == "stored")
    host.confirmJoin(join)
    try await subscription.value
  }

  @Test
  func failingAccessTokenCallbackStillLetsTheJoinGo() async throws {
    struct Failure: Error {}
    let host = await RealtimeTestHost(
      options: RealtimeClientOptions(
        headers: ["Authorization": "Bearer stored"],
        accessToken: { throw Failure() },
        handleAppLifecycle: false
      ))
    let channel = host.client.channel("room")
    let subscription = Task { try await channel.subscribe() }

    let join = try await host.receive(event: ChannelEvent.join)
    #expect(join.payload["access_token"] == "stored")
    host.confirmJoin(join)
    try await subscription.value
  }

  // MARK: Idle disconnect

  @Test
  func removingTheLastSubscribedChannelKeepsANeverSubscribedOneConnected() async throws {
    let host = await RealtimeTestHost(
      options: RealtimeClientOptions(
        disconnectOnEmptyChannelsAfter: .seconds(5), handleAppLifecycle: false))
    let subscribed = host.client.channel("subscribed")
    let join = try await subscribe(subscribed, on: host)
    _ = host.client.channel("never-subscribed")

    let removal = Task { await host.client.removeChannel(subscribed) }
    _ = try await host.receive(event: ChannelEvent.leave)
    host.server?.send(close(join))
    await removal.value

    #expect(await host.client.idleDisconnectTimer == nil)
    #expect(host.client.status == .connected)
  }

  // MARK: Released client and removed channel

  @Test
  func newHandleSubscribesAfterTheOldHandlesRemovalEnds() async throws {
    let host = await RealtimeTestHost()
    let old = host.client.channel("room")
    let oldJoin = try await subscribe(old, on: host)
    let removal = Task { await host.client.removeChannel(old) }
    let leave = try await host.receive(event: ChannelEvent.leave)

    let new = host.client.channel("room")
    #expect(new !== old)
    let subscription = Task { try await new.subscribe() }
    let broadcast = Task { try await new.broadcast(event: "e", payload: ["a": 1] as JSONObject) }
    #expect(await waitUntil { await host.client.removalWaiters["room"]?.count == 2 })

    host.reply(to: leave)
    host.server?.send(close(oldJoin))
    let join = try await host.receive {
      $0.event == ChannelEvent.join && $0.joinRef != oldJoin.joinRef
    }
    host.confirmJoin(join)

    try await subscription.value
    await removal.value
    #expect(new.status == .subscribed)
    #expect(host.client.channels.contains(new))
    // A broadcast parked behind the removal acts on a new channel, which is not subscribed yet.
    await expectError(.notSubscribed) { try await broadcast.value }
  }

  @Test
  func cancellingAnActionParkedBehindARemovalLeavesNothingBehind() async throws {
    let host = await RealtimeTestHost()
    let old = host.client.channel("room")
    let oldJoin = try await subscribe(old, on: host)
    let removal = Task { await host.client.removeChannel(old) }
    _ = try await host.receive(event: ChannelEvent.leave)

    let new = host.client.channel("room")
    let subscription = Task { try await new.subscribe() }
    #expect(await waitUntil { await host.client.removalWaiters["room"]?.count == 1 })
    subscription.cancel()

    await #expect(throws: CancellationError.self) { try await subscription.value }
    #expect(await host.client.removalWaiters["room"] == nil)
    host.server?.send(close(oldJoin))
    await removal.value
    #expect(await !host.client.hasRecord(for: "room"))
    #expect(host.frames.filter { $0.event == ChannelEvent.join }.count == 1)
    #expect(new.status == .unsubscribed)
  }

  @Test
  func cancelledUnsubscribeParkedBehindARemovalStillLeaves() async throws {
    let host = await RealtimeTestHost()
    let old = host.client.channel("room")
    let oldJoin = try await subscribe(old, on: host)
    let removal = Task { await host.client.removeChannel(old) }
    let oldLeave = try await host.receive(event: ChannelEvent.leave)

    let new = host.client.channel("room")
    let subscription = Task { try await new.subscribe() }
    #expect(await waitUntil { await host.client.removalWaiters["room"]?.count == 1 })
    let unsubscription = Task { await new.unsubscribe() }
    #expect(await waitUntil { await host.client.removalWaiters["room"]?.count == 2 })
    unsubscription.cancel()

    host.reply(to: oldLeave)
    host.server?.send(close(oldJoin))
    await removal.value
    let join = try await host.receive {
      $0.event == ChannelEvent.join && $0.joinRef != oldJoin.joinRef
    }
    _ = try await host.receive { $0.event == ChannelEvent.leave && $0.joinRef == join.joinRef }

    await unsubscription.value
    await #expect(throws: CancellationError.self) { try await subscription.value }
    #expect(new.status == .unsubscribed)
  }

  @Test
  func spentHandleWokenFromARemovalWaitThrowsChannelRemoved() async throws {
    let host = await RealtimeTestHost()
    let old = host.client.channel("room")
    try await subscribe(old, on: host)
    let removal = Task { await host.client.removeChannel(old) }
    _ = try await host.receive(event: ChannelEvent.leave)

    let new = host.client.channel("room")
    let subscription = Task { try await new.subscribe() }
    #expect(await waitUntil { await host.client.removalWaiters["room"]?.count == 1 })
    await host.client.removeChannel(new)

    // Wakes the action while the old removal still holds the topic, as a later removal of the
    // topic would when the action runs.
    await host.client.removalEnded("room")

    await expectError(.channelRemoved) {
      try await withTimeout(.seconds(5)) {
        try await withTaskCancellationHandler {
          try await subscription.value
        } onCancel: {
          subscription.cancel()
        }
      }
    }
    #expect(await host.client.removalWaiters["room"] == nil)
    removal.cancel()
  }

  @Test
  func removingAChannelOfAnotherClientIsANoOp() async throws {
    let host = await RealtimeTestHost()
    let channel = host.client.channel("room")
    try await subscribe(channel, on: host)
    let other = RealtimeClient(
      url: URL(string: "http://localhost:54321/realtime/v1")!,
      options: RealtimeClientOptions(handleAppLifecycle: false)
    )
    _ = other.channel("room")

    await other.removeChannel(channel)

    #expect(host.client.channels.contains(channel))
    #expect(channel.status == .subscribed)
    try await channel.broadcast(event: "e", payload: ["a": 1] as JSONObject)
    #expect(await host.client.hasRecord(for: "room"))
  }

  @Test
  func releasedClientActionsThrowClientReleased() async throws {
    func makeChannel() -> RealtimeChannel {
      let client = RealtimeClient(
        url: URL(string: "http://localhost:54321/realtime/v1")!,
        options: RealtimeClientOptions(handleAppLifecycle: false)
      )
      return client.channel("room")
    }
    let channel = makeChannel()
    try #require(await waitUntil { channel.client == nil })

    await expectError(.clientReleased) { try await channel.subscribe() }
    await expectError(.clientReleased) {
      try await channel.broadcast(event: "e", payload: ["a": 1] as JSONObject)
    }
    await expectError(.clientReleased) { try await channel.broadcast(event: "e", data: Data()) }
    await expectError(.clientReleased) { try await channel.track(["a": 1] as JSONObject) }
    await expectError(.clientReleased) { try await channel.untrack() }
    await expectError(.clientReleased) {
      try await channel.httpSend(event: "e", payload: ["a": 1] as JSONObject)
    }
  }

  @Test
  func spentHandleActionsThrowChannelRemoved() async throws {
    let host = await RealtimeTestHost(
      options: RealtimeClientOptions(
        disconnectOnEmptyChannelsAfter: .seconds(5), handleAppLifecycle: false))
    let channel = host.client.channel("room")
    let join = try await subscribe(channel, on: host)
    let removal = Task { await host.client.removeChannel(channel) }
    _ = try await host.receive(event: ChannelEvent.leave)
    host.server?.send(close(join))
    await removal.value
    #expect(await host.client.idleDisconnectTimer != nil)

    await expectError(.channelRemoved) { try await channel.subscribe() }
    await expectError(.channelRemoved) {
      try await channel.broadcast(event: "e", payload: ["a": 1] as JSONObject)
    }
    await expectError(.channelRemoved) { try await channel.track(["a": 1] as JSONObject) }
    await expectError(.channelRemoved) { try await channel.untrack() }
    await expectError(.channelRemoved) {
      try await channel.httpSend(event: "e", payload: ["a": 1] as JSONObject)
    }

    // Reads keep the last status, and new streams end at once.
    #expect(channel.status == .subscribed)
    var statuses: [RealtimeChannelStatus] = []
    for await status in channel.statusChanges() {
      statuses.append(status)
    }
    #expect(statuses.count <= 1)
    // A spent handle never reaches the core, so the idle disconnect stays scheduled.
    #expect(await host.client.idleDisconnectTimer != nil)
    #expect(!host.client.channels.contains(channel))
  }

  @Test
  func aClientWaitingToReconnectIsReleased() async throws {
    final class WeakBox: @unchecked Sendable {
      weak var client: RealtimeClient?
    }
    let box = WeakBox()
    let clock = TestClock<Duration>()
    let servers = LockIsolated<[FakeWebSocket]>([])

    func scope() async throws {
      let client = RealtimeClient(
        url: URL(string: "http://localhost:54321/realtime/v1")!,
        options: RealtimeClientOptions(handleAppLifecycle: false),
        wsTransport: { _, _ in
          let (socket, server) = FakeWebSocket.fakes()
          servers.withValue { $0.append(server) }
          return socket
        },
        http: HTTPClient(transport: RecordingTransport()),
        clock: clock
      )
      box.client = client
      try await client.connect()
      servers.value.last?.close(code: 1006, reason: "dropped")
      _ = await waitUntil { client.status != .connected }
    }
    try await scope()

    #expect(await waitUntil(timeout: 5) { box.client == nil })
  }

  // MARK: Helpers

  @discardableResult
  private func subscribe(
    _ channel: RealtimeChannel, on host: RealtimeTestHost
  ) async throws -> RealtimeMessage {
    let subscription = Task { try await channel.subscribe() }
    let join = try await host.receive {
      $0.event == ChannelEvent.join && $0.topic == channel.wireTopic
    }
    host.confirmJoin(join)
    try await subscription.value
    return join
  }

  /// The server's `phx_close` for `join`.
  private func close(_ join: RealtimeMessage) -> RealtimeMessage {
    RealtimeMessage(
      joinRef: join.joinRef, ref: nil, topic: join.topic, event: ChannelEvent.close, payload: [:])
  }

  private func expectError(
    _ expected: RealtimeError,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ action: () async throws -> Void
  ) async {
    do {
      try await action()
      Issue.record("Expected \(expected.kind)", sourceLocation: sourceLocation)
    } catch let error as RealtimeError {
      #expect(error.isSameFailure(as: expected), sourceLocation: sourceLocation)
    } catch {
      Issue.record("Unexpected \(error)", sourceLocation: sourceLocation)
    }
  }
}
