//
//  InboxTests.swift
//  RealtimeTests
//

import Clocks
import ConcurrencyExtras
import Foundation
import Helpers
import TestHelpers
import Testing

@testable import Realtime

#if canImport(UIKit)
  import UIKit
#elseif canImport(AppKit)
  import AppKit
#endif

/// Which input of the access token race reaches the client first.
enum TokenRace: Sendable {
  /// The callback returns a token before the request timeout.
  case callWins
  /// The callback does not return within the request timeout.
  case timeoutWins
  /// The callback returns `nil` before the request timeout.
  case callReturnsNil
}

/// The client's inbox: every edge yields one input, one pump applies them in order, and a stamp
/// drops the inputs of work that was replaced or stopped.
@Suite(.timeLimit(.minutes(1)), .mainSerialExecutorSerialized)
struct InboxTests {
  // MARK: Order

  @Test
  func timerFireCannotOvertakeAnEarlierFrame() async throws {
    let host = await RealtimeTestHost()
    try await host.client.connect()
    let first = try #require(await host.client.timers.token(for: .heartbeat))
    host.client.inbox.yield(.timerFired(.heartbeat, token: first))
    let heartbeat = try await host.receive(event: ChannelEvent.heartbeat)
    let token = try #require(await host.client.timers.token(for: .heartbeat))
    let generation = await host.client.generation
    let reply = RealtimeMessage(
      joinRef: nil, ref: heartbeat.ref, topic: "phoenix", event: ChannelEvent.reply,
      payload: ["status": "ok", "response": [:]])

    host.client.inbox.yield(.socket(.frame(reply), generation: generation))
    host.client.inbox.yield(.timerFired(.heartbeat, token: token))
    await host.client.flushInbox()

    // A fire applied before the reply finds the heartbeat unanswered and fails the socket.
    #expect(await host.client.status.isConnected)
    _ = try await host.receive {
      $0.event == ChannelEvent.heartbeat && $0.ref != heartbeat.ref
    }
  }

  // MARK: Stamps

  @Test
  func framesFromAnOldSocketGenerationAreDropped() async throws {
    let host = await RealtimeTestHost()
    let channel = await host.client.channel("room")
    let broadcasts = await channel.broadcasts(event: "ping")
    try await host.subscribe(channel)
    let generation = await host.client.generation
    let frame = RealtimeMessage(
      joinRef: nil, ref: nil, topic: channel.wireTopic, event: ChannelEvent.broadcast,
      payload: ["event": "ping", "payload": ["n": 1]])

    host.client.inbox.yield(.socket(.frame(frame), generation: generation - 1))
    host.client.inbox.yield(.socket(.closed(code: nil, reason: "old"), generation: generation - 1))
    host.client.inbox.yield(.socket(.frame(frame), generation: generation))
    await host.client.flushInbox()
    await host.client.finishStreams(of: channel)

    var received: [BroadcastMessage] = []
    for await message in broadcasts {
      received.append(message)
    }
    #expect(received.count == 1)
    #expect(await host.client.status.isConnected)
  }

  @Test
  func aStaleConnectResultIsDropped() async throws {
    // Each connect waits until the test ends it or the attempt is cancelled.
    let attempts = LockIsolated<[AsyncStream<Void>.Continuation]>([])
    let client = RealtimeClient(
      url: URL(string: "http://localhost:54321/realtime/v1")!,
      options: RealtimeClientOptions(handleAppLifecycle: false),
      wsTransport: { _, _ in
        let (open, continuation) = AsyncStream<Void>.makeStream()
        attempts.withValue { $0.append(continuation) }
        for await _ in open {}
        throw CancellationError()
      },
      http: HTTPClient(transport: RecordingTransport()),
      clock: TestClock<Duration>()
    )
    defer { attempts.value.forEach { $0.finish() } }

    let first = Task { try await client.connect() }
    #expect(await waitUntil(timeout: 5) { await client.connectAttempt != nil })
    let stale = try #require(await client.connectAttempt?.id)
    await client.disconnect()
    await #expect(throws: CancellationError.self) { try await first.value }
    let second = Task { try await client.connect() }
    #expect(await waitUntil(timeout: 5) { await client.connectAttempt != nil })
    let current = try #require(await client.connectAttempt?.id)
    #expect(current != stale)

    let (late, _) = FakeWebSocket.fakes()
    client.inbox.yield(.connectEnded(.success(late), attempt: stale))
    client.inbox.yield(.connectEnded(.failure(URLError(.timedOut)), attempt: stale))
    await client.flushInbox()

    #expect(late.isClosed)
    #expect(await client.status.isSame(as: .connecting(attempt: 1)))
    #expect(await client.socket == nil)

    let (socket, _) = FakeWebSocket.fakes()
    client.inbox.yield(.connectEnded(.success(socket), attempt: current))
    try await second.value
    #expect(await client.status.isConnected)
    #expect(await client.socket === socket)
    await client.disconnect()
  }

  @Test
  func aStaleTimerTokenIsDropped() async throws {
    let host = await RealtimeTestHost(
      options: RealtimeClientOptions(requestTimeout: .seconds(10), handleAppLifecycle: false))
    let channel = await host.client.channel("room")
    let subscription = Task { try await channel.subscribe() }
    let join = try await host.receive(event: ChannelEvent.join)
    let timeout = TimerID.joinTimeout(channel: channel.id, ref: join.ref ?? "")
    let token = try #require(await host.client.timers.token(for: timeout))

    host.client.inbox.yield(.timerFired(timeout, token: token + 1))
    await host.client.flushInbox()
    #expect(await channel.status.isSame(as: .subscribing(attempt: 1)))

    host.client.inbox.yield(.timerFired(timeout, token: token))
    await host.client.flushInbox()
    #expect(
      await {
        if case .resubscribing(1, _, _) = await channel.status { true } else { false }
      }())

    // A timer fires once: its token is spent.
    host.client.inbox.yield(.timerFired(timeout, token: token))
    await host.client.flushInbox()
    #expect(
      await {
        if case .resubscribing(1, _, _) = await channel.status { true } else { false }
      }())
    subscription.cancel()
    _ = await subscription.result
  }

  @Test
  func aStaleRetryTokenIsDropped() async throws {
    let host = await RealtimeTestHost()
    try await host.client.connect()
    host.server?.close(code: 1006, reason: "dropped")
    await host.waitUntil {
      if case .reconnecting = await host.client.status { true } else { false }
    }
    let token = try #require(await host.client.retryTimer?.token)

    host.client.inbox.yield(.retryTimerFired(token: token + 1))
    await host.client.flushInbox()
    #expect(
      await {
        if case .reconnecting = await host.client.status { true } else { false }
      }())
    #expect(host.connectCount == 1)

    host.client.inbox.yield(.retryTimerFired(token: token))
    await host.client.flushInbox()
    #expect(await host.client.retryTimer == nil)
    await host.waitUntil { await host.client.status.isConnected }
    #expect(host.connectCount == 2)
  }

  @Test
  func aStaleIdleTokenIsDropped() async throws {
    let host = await RealtimeTestHost(
      options: RealtimeClientOptions(
        disconnectOnEmptyChannelsAfter: .seconds(5), handleAppLifecycle: false))
    let channel = await host.client.channel("room")
    let join = try await host.subscribe(channel)
    let removal = Task { await host.client.removeChannel(channel) }
    _ = try await host.receive(event: ChannelEvent.leave)
    host.sendClose(for: join)
    await removal.value
    let token = try #require(await host.client.idleDisconnectTimer?.token)

    host.client.inbox.yield(.idleTimerFired(token: token + 1))
    await host.client.flushInbox()
    #expect(await host.client.status.isConnected)

    host.client.inbox.yield(.idleTimerFired(token: token))
    await host.client.flushInbox()
    #expect(await host.client.status.isSame(as: .disconnected(nil)))
  }

  @Test(arguments: [TokenRace.callWins, .timeoutWins, .callReturnsNil])
  func tokenRaceLetsExactlyOneJoinGo(_ race: TokenRace) async throws {
    // Each call waits until the test ends it or the call is cancelled.
    let calls = LockIsolated<[AsyncStream<Void>.Continuation]>([])
    let host = await RealtimeTestHost(
      options: RealtimeClientOptions(
        headers: ["Authorization": "Bearer stored"],
        requestTimeout: .seconds(5),
        accessToken: {
          let (returned, continuation) = AsyncStream<Void>.makeStream()
          calls.withValue { $0.append(continuation) }
          for await _ in returned {}
          switch race {
          case .callWins: return "fresh"
          case .timeoutWins: return "late"
          case .callReturnsNil: return nil
          }
        },
        handleAppLifecycle: false
      ))
    defer { calls.value.forEach { $0.finish() } }
    let channel = await host.client.channel("room")
    let subscription = Task { try await channel.subscribe() }
    #expect(await waitUntil(timeout: 5) { calls.value.count == 1 })
    let fetch = try #require(await host.client.tokenFetch)

    switch race {
    case .callWins, .callReturnsNil:
      calls.value[0].finish()
    case .timeoutWins:
      await host.clock.advance(by: .seconds(5))
    }
    let join = try await host.receive(event: ChannelEvent.join)
    host.confirmJoin(join)
    try await subscription.value

    // The loser was cancelled. Once both edges are done, every input they yielded is in the
    // inbox, and the flush applies it.
    #expect(race == .timeoutWins ? fetch.call.isCancelled : fetch.timeout.isCancelled)
    await host.clock.advance(by: .seconds(5))
    calls.value.forEach { $0.finish() }
    await fetch.call.value
    await fetch.timeout.value
    await host.client.flushInbox()

    let expected = race == .callWins ? "fresh" : "stored"
    #expect(join.payload["access_token"] == .string(expected))
    #expect(host.frames.filter { $0.event == ChannelEvent.join }.count == 1)
    #expect(await host.client.accessToken == expected)
    #expect(await host.client.tokenFetch == nil)
  }

  // MARK: Cancellation

  @Test
  func cancelBeforeParkSendsNothing() async throws {
    let host = await RealtimeTestHost()
    // Connected, so a join would go out at once.
    try await host.client.connect()
    let channel = await host.client.channel("room")
    let cancelled = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      try await channel.subscribe()
    }

    await #expect(throws: CancellationError.self) { try await cancelled.value }
    await host.client.flushInbox()
    #expect(await !host.client.hasRecord(for: "room"))
    // Frames leave in order, so once this join is in, any frame for "room" would be too.
    try await host.subscribe(host.client.channel("barrier"))
    #expect(host.frames.filter { $0.topic == channel.wireTopic }.isEmpty)
    #expect(await channel.status == .unsubscribed)
  }

  @Test
  func cancelAfterParkRollsBackTheJoin() async throws {
    let host = await RealtimeTestHost()
    let channel = await host.client.channel("room")
    let subscription = Task { try await channel.subscribe() }
    let join = try await host.receive(event: ChannelEvent.join)

    subscription.cancel()

    await #expect(throws: CancellationError.self) { try await subscription.value }
    await host.client.flushInbox()
    let leave = try await host.receive(event: ChannelEvent.leave)
    #expect(leave.joinRef == join.ref)
    #expect(await channel.status == .unsubscribed)
  }

  // MARK: Lifecycle

  #if os(iOS) || os(tvOS) || os(visionOS) || os(macOS)
    @Test
    func appLifecycleEventsGoThroughTheInbox() async throws {
      let host = await RealtimeTestHost(options: RealtimeClientOptions(handleAppLifecycle: true))
      try await host.client.connect()

      // Only the background notification: a foreground one would wake every other client in
      // the process that is waiting to reconnect.
      await MainActor.run {
        #if canImport(UIKit)
          let background = UIApplication.didEnterBackgroundNotification
        #else
          let background = NSApplication.didResignActiveNotification
        #endif
        NotificationCenter.default.post(name: background, object: nil)
      }
      await host.client.flushInbox()

      #expect(await host.client.wasConnectedBeforeBackground)
    }
  #endif

  @Test
  func releasingTheClientEndsThePumpAndClosesTheSocket() async throws {
    final class WeakBox: @unchecked Sendable {
      weak var client: RealtimeClient?
    }
    let box = WeakBox()
    let servers = LockIsolated<[FakeWebSocket]>([])

    func scope() async throws -> AsyncStream<Input>.Continuation {
      let client = RealtimeClient(
        url: URL(string: "http://localhost:54321/realtime/v1")!,
        options: RealtimeClientOptions(handleAppLifecycle: false),
        wsTransport: { _, _ in
          let (socket, server) = FakeWebSocket.fakes()
          servers.withValue { $0.append(server) }
          return socket
        },
        http: HTTPClient(transport: RecordingTransport()),
        clock: TestClock<Duration>()
      )
      box.client = client
      try await client.connect()
      await client.flushInbox()
      return client.inbox
    }
    let inbox = try await scope()
    let server = try #require(servers.value.last)

    #expect(await waitUntil(timeout: 5) { box.client == nil && server.isClosed })
    #expect(server.isClosed)
    // `deinit` finished the inbox, which ends the pump's loop.
    #expect(
      {
        if case .terminated = inbox.yield(.appBackground) { true } else { false }
      }())
  }

  @Test
  func aSocketThatOpensWhileTheClientIsReleasedIsClosed() async {
    // Serial, so the pump cannot start before the client is gone: the connect result waits in
    // the inbox, and the pump finds no client when it reads it.
    await withMainSerialExecutor {
      let (socket, _) = FakeWebSocket.fakes()
      var client: RealtimeClient? = makeClient()
      client?.inbox.yield(.connectEnded(.success(socket), attempt: 1))
      client = nil

      await waitUntil(timeout: 5) { socket.isClosed }

      #expect(socket.isClosed)
      #expect(socket.closeReason == "Client deallocated")
    }
  }

  @Test
  func aFlushYieldedBeforeTheClientIsReleasedStillResumes() async {
    await withMainSerialExecutor {
      await withCheckedContinuation { continuation in
        var client: RealtimeClient? = makeClient()
        client?.inbox.yield(.flush(continuation))
        client = nil
      }
    }
  }

  // MARK: Helpers

  private func makeClient() -> RealtimeClient {
    RealtimeClient(
      url: URL(string: "http://localhost:54321/realtime/v1")!,
      options: RealtimeClientOptions(handleAppLifecycle: false),
      wsTransport: { _, _ in FakeWebSocket.fakes().0 },
      http: HTTPClient(transport: RecordingTransport()),
      clock: TestClock<Duration>()
    )
  }
}

extension RealtimeClient {
  /// Whether the core saw the socket connected when the app last entered the background.
  fileprivate var wasConnectedBeforeBackground: Bool { core.wasConnectedBeforeBackground }
}
