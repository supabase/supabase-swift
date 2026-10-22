import Clocks
import ConcurrencyExtras
import Foundation
import Helpers
import TestHelpers
import Testing

@testable import Realtime

@Suite
struct RealtimeChannelSubscriptionTests {
  // MARK: - Subscribe

  @Test
  func newChannelIsUnsubscribed() async {
    let h = Harness()
    let channel = await h.client.channel("room")

    #expect(await channel.status == .unsubscribed)
    #expect(await channel.joinRef == nil)
  }

  @Test
  func subscribeSendsJoinAndCompletesOnServerConfirmation() async throws {
    let h = Harness()
    let channel = await h.client.channel("room")

    let join = try await h.subscribe(channel)

    #expect(await channel.status == .subscribed)
    #expect(await channel.joinRef == join.ref)
    #expect(h.sent(ChannelEvent.join).count == 1)
  }

  @Test
  func subscribeWhileSubscribedIsNoOp() async throws {
    let h = Harness()
    let channel = await h.client.channel("room")
    _ = try await h.subscribe(channel)

    try await channel.subscribe()

    #expect(h.sent(ChannelEvent.join).count == 1)
  }

  @Test
  func concurrentSubscribesShareOneJoin() async throws {
    let h = Harness()
    let channel = await h.client.channel("room")

    async let first: Void = channel.subscribe()
    async let second: Void = channel.subscribe()
    _ = try #require(await h.received(ChannelEvent.join))
    await channel.didReceiveSubscribedOK()

    try await first
    try await second
    #expect(await channel.status == .subscribed)
    #expect(h.sent(ChannelEvent.join).count == 1)
  }

  @Test
  func subscribeRetriesAfterTimeoutThenSucceeds() async throws {
    let h = Harness(timeout: .seconds(10), maxRetryAttempts: 3)
    let channel = await h.client.channel("room")

    let subscription = Task { try await channel.subscribe() }
    let firstJoin = try #require(await h.received(ChannelEvent.join))
    // The attempt times out at 10s; the first retry waits at most 1.25s.
    await h.clock.advance(by: .seconds(12))
    let secondJoin = try #require(await h.received(ChannelEvent.join))
    try h.confirm(secondJoin)

    try await subscription.value
    #expect(await channel.status == .subscribed)
    #expect(secondJoin.ref != firstJoin.ref)
    #expect(await channel.joinRef == secondJoin.ref)
  }

  @Test
  func subscribeThrowsMaxRetryAttemptsReachedWhenNoAttemptIsConfirmed() async throws {
    let h = Harness(timeout: .seconds(10), maxRetryAttempts: 2)
    let channel = await h.client.channel("room")

    let subscription = Task { try await channel.subscribe() }
    _ = try #require(await h.received(ChannelEvent.join))
    await h.clock.advance(by: .seconds(12))
    _ = try #require(await h.received(ChannelEvent.join))
    await h.clock.advance(by: .seconds(10))

    let error = await #expect(throws: RealtimeError.self) { try await subscription.value }
    #expect(error?.kind == .maxRetryAttemptsReached)
    #expect(await channel.status == .unsubscribed)
    #expect(await channel.joinRef == nil)
    #expect(h.sent(ChannelEvent.join).count == 2)
  }

  /// Issue #1145 (defect 2): a transient socket connect failure must enter the retry ladder
  /// like a timeout instead of aborting the subscribe.
  @Test
  func subscribeRetriesWhenSocketConnectFailsTransiently() async throws {
    let h = Harness(maxRetryAttempts: 3, failedConnects: 1)
    let channel = await h.client.channel("room")
    var statuses = await h.client.statusChanges().makeAsyncIterator()

    let subscription = Task { try await channel.subscribe() }
    #expect(await statuses.next() == .disconnected)
    #expect(await statuses.next() == .connecting)
    #expect(await statuses.next() == .disconnected)
    await h.clock.advance(by: .seconds(2))
    try h.confirm(try #require(await h.received(ChannelEvent.join)))

    try await subscription.value
    #expect(await channel.status == .subscribed)
    #expect(h.connects.value == 2)
  }

  /// Issue #1145 (defect 2): connect failures must not surface as `CancellationError`, which
  /// callers attribute to their own task.
  @Test
  func persistentConnectFailureThrowsMaxRetryAttemptsReached() async throws {
    let h = Harness(maxRetryAttempts: 2, failedConnects: .max)
    let channel = await h.client.channel("room")
    var statuses = await h.client.statusChanges().makeAsyncIterator()

    let subscription = Task { try await channel.subscribe() }
    #expect(await statuses.next() == .disconnected)
    #expect(await statuses.next() == .connecting)
    #expect(await statuses.next() == .disconnected)
    await h.clock.advance(by: .seconds(2))

    let error = await #expect(throws: RealtimeError.self) { try await subscription.value }
    #expect(error?.kind == .maxRetryAttemptsReached)
    #expect(await channel.status == .unsubscribed)
  }

  @Test
  func joinCarriesThePostgresChangesOfOpenStreams() async throws {
    let h = Harness()
    let channel = await h.client.channel("public:users")
    let inserts = await channel.postgresChanges(InsertAction.self, table: "users")

    let subscription = Task { try await channel.subscribe() }
    let join = try #require(await h.received(ChannelEvent.join))
    let changes = join.payload["config"]?.objectValue?["postgres_changes"]?.arrayValue
    #expect(changes?.count == 1)
    #expect(changes?.first?.objectValue?["table"]?.stringValue == "users")
    // The `system` confirmation path.
    await channel.onMessage(
      RealtimeMessageV2(
        joinRef: join.ref, ref: nil, topic: channel.topic, event: ChannelEvent.system,
        payload: ["status": "ok"]
      )
    )

    try await subscription.value
    #expect(await channel.status == .subscribed)
    withExtendedLifetime(inserts) {}
  }

  @Test
  func confirmationOutsideSubscribeIsIgnored() async {
    let h = Harness()
    let channel = await h.client.channel("room")

    await channel.didReceiveSubscribedOK()

    #expect(await channel.status == .unsubscribed)
  }

  // MARK: - Cancellation and server close

  @Test
  func cancellingSubscribeLeavesChannelUnsubscribed() async throws {
    let h = Harness()
    let channel = await h.client.channel("room")

    let subscription = Task { try await channel.subscribe() }
    _ = try #require(await h.received(ChannelEvent.join))
    subscription.cancel()

    await #expect(throws: CancellationError.self) { try await subscription.value }
    #expect(await channel.status == .unsubscribed)
    #expect(await channel.joinRef == nil)
  }

  /// A server close that aborts an in-flight subscribe surfaces as `channelClosedByServer`:
  /// never as `CancellationError` (the caller's own task) nor `maxRetryAttemptsReached`.
  @Test
  func serverCloseDuringSubscribeThrowsChannelClosedByServer() async throws {
    let h = Harness(maxRetryAttempts: 1)
    let channel = await h.client.channel("room")

    let subscription = Task { try await channel.subscribe() }
    let join = try #require(await h.received(ChannelEvent.join))
    try h.close(join)

    let error = await #expect(throws: RealtimeError.self) { try await subscription.value }
    #expect(error?.kind == .channelClosedByServer)
    #expect(await channel.status == .unsubscribed)
  }

  @Test
  func closeForStaleJoinRefIsIgnored() async throws {
    let h = Harness()
    let channel = await h.client.channel("room")
    let join = try await h.subscribe(channel)

    #expect(await channel.didReceiveClose(joinRef: "stale-join-ref") == false)
    #expect(await channel.status == .subscribed)

    #expect(await channel.didReceiveClose(joinRef: join.ref) == true)
    #expect(await channel.status == .unsubscribed)
    #expect(await channel.joinRef == nil)
  }

  @Test
  func closeWithoutJoinRefUnsubscribes() async throws {
    let h = Harness()
    let channel = await h.client.channel("room")
    _ = try await h.subscribe(channel)

    #expect(await channel.didReceiveClose() == true)

    #expect(await channel.status == .unsubscribed)
    #expect(await channel.joinRef == nil)
  }

  // MARK: - Reconnect

  @Test
  func resetForReconnectLetsTheNextSubscribeRejoin() async throws {
    let h = Harness()
    let channel = await h.client.channel("room")
    let firstJoin = try await h.subscribe(channel)

    await channel.resetForReconnect()
    #expect(await channel.status == .unsubscribed)
    #expect(await channel.joinRef == nil)

    let secondJoin = try await h.subscribe(channel)
    #expect(secondJoin.ref != firstJoin.ref)
    #expect(h.sent(ChannelEvent.join).count == 2)
  }

  @Test
  func resetForReconnectAbortsAnInFlightSubscribe() async throws {
    let h = Harness()
    let channel = await h.client.channel("room")

    let subscription = Task { try await channel.subscribe() }
    let firstJoin = try #require(await h.received(ChannelEvent.join))
    await channel.resetForReconnect()

    await #expect(throws: (any Error).self) { try await subscription.value }
    #expect(await channel.status == .unsubscribed)

    let secondJoin = try await h.subscribe(channel)
    #expect(secondJoin.ref != firstJoin.ref)
  }

  /// Issue #1556: the first subscribe is cancelled by a reset while a newer attempt has already
  /// joined. Its failure must leave the newer attempt's state and `joinRef` alone.
  @Test(.timeLimit(.minutes(1)))
  func staleSubscribeFailureLeavesReplacementSubscribeUntouched() async throws {
    let gate = Gate()
    let h = Harness(maxRetryAttempts: 1)
    // The first `phx_join` stays in its send, which a cancel cannot cut short, so the attempt
    // fails only after the newer one has joined.
    let joinSends = LockIsolated(0)
    h.socket.onSend { frame in
      guard case .text(let text) = frame, text.contains("\"\(ChannelEvent.join)\"") else { return }
      let send = joinSends.withValue {
        $0 += 1
        return $0
      }
      if send == 1 { await gate.park() }
    }
    let channel = await h.client.channel("room")

    let firstSubscribe = Task { try await channel.subscribe() }
    let firstJoin = try #require(await h.received(ChannelEvent.join))
    #expect(await waitUntil { gate.isParked })

    await channel.resetForReconnect()
    let secondSubscribe = Task { try await channel.subscribe() }
    let secondJoin = try #require(await h.received(ChannelEvent.join))
    #expect(secondJoin.ref != firstJoin.ref)
    #expect(await channel.joinRef == secondJoin.ref)

    gate.open()
    await #expect(throws: (any Error).self) { try await firstSubscribe.value }

    try #require(await channel.status == .subscribing)
    #expect(await channel.joinRef == secondJoin.ref)
    #expect(h.sent(ChannelEvent.join).count == 2)

    try h.confirm(secondJoin)
    try await secondSubscribe.value
    #expect(await channel.status == .subscribed)
    #expect(h.sent(ChannelEvent.join).count == 2)
  }

  /// A server close that cancels a subscribe still surfaces as `channelClosedByServer` to that
  /// caller when a newer attempt has replaced it by the time it fails.
  @Test(.timeLimit(.minutes(1)))
  func serverCloseDuringStaleSubscribeStillSurfacesTypedError() async throws {
    let gate = Gate()
    let h = Harness(maxRetryAttempts: 1)
    // The first `phx_join` stays in its send, which a cancel cannot cut short, so the attempt
    // fails only after the newer one has joined.
    let joinSends = LockIsolated(0)
    h.socket.onSend { frame in
      guard case .text(let text) = frame, text.contains("\"\(ChannelEvent.join)\"") else { return }
      let send = joinSends.withValue {
        $0 += 1
        return $0
      }
      if send == 1 { await gate.park() }
    }
    let channel = await h.client.channel("room")

    let firstSubscribe = Task { try await channel.subscribe() }
    let firstJoin = try #require(await h.received(ChannelEvent.join))
    #expect(await waitUntil { gate.isParked })
    #expect(await channel.didReceiveClose())

    let secondSubscribe = Task { try await channel.subscribe() }
    let secondJoin = try #require(await h.received(ChannelEvent.join))
    #expect(secondJoin.ref != firstJoin.ref)

    gate.open()
    let error = await #expect(throws: RealtimeError.self) { try await firstSubscribe.value }
    #expect(error?.kind == .channelClosedByServer)

    try #require(await channel.status == .subscribing)
    #expect(await channel.joinRef == secondJoin.ref)

    try h.confirm(secondJoin)
    try await secondSubscribe.value
    #expect(await channel.status == .subscribed)
  }

  /// A subscribe cancelled while its connect is in flight must not write `joinRef` or send a
  /// `phx_join` once the connect returns; the attempt that replaced it owns the join.
  @Test(.timeLimit(.minutes(1)))
  func cancelledStaleSubscribeNeverJoinsAfterReconnect() async throws {
    let gate = Gate()
    let h = Harness(
      maxRetryAttempts: 1,
      onConnect: { attempt in
        if attempt == 1 { await gate.park() }
      })
    let channel = await h.client.channel("room")

    // Without the cancellation check the stale attempt parks on a join waiter the newer attempt
    // then replaces, so it never finishes: wait for it with a bound instead of awaiting it.
    let firstFinished = LockIsolated(false)
    let firstSubscribe = Task {
      defer { firstFinished.setValue(true) }
      try await channel.subscribe()
    }
    #expect(await waitUntil { gate.isParked })

    await channel.resetForReconnect()
    let secondSubscribe = Task { try await channel.subscribe() }

    gate.open()
    let join = try #require(await h.received(ChannelEvent.join))
    try #require(await waitUntil(timeout: 2) { firstFinished.value })
    await #expect(throws: (any Error).self) { try await firstSubscribe.value }

    #expect(h.sent(ChannelEvent.join).count == 1)
    #expect(await channel.joinRef == join.ref)
    try #require(await channel.status == .subscribing)

    try h.confirm(join)
    try await secondSubscribe.value
    #expect(h.sent(ChannelEvent.join).count == 1)
  }

  // MARK: - Unsubscribe

  @Test
  func unsubscribeWhenUnsubscribedIsNoOp() async {
    let h = Harness()
    let channel = await h.client.channel("room")

    await channel.unsubscribe()

    #expect(await channel.status == .unsubscribed)
    #expect(h.sent(ChannelEvent.leave).isEmpty)
  }

  @Test
  func unsubscribeSendsLeaveAndWaitsForServerClose() async throws {
    let h = Harness()
    let channel = await h.client.channel("room")
    let join = try await h.subscribe(channel)

    let unsubscription = Task { await channel.unsubscribe() }
    _ = try #require(await h.received(ChannelEvent.leave))
    try h.close(join)
    await unsubscription.value

    #expect(await channel.status == .unsubscribed)
    #expect(await channel.joinRef == nil)
    #expect(h.sent(ChannelEvent.leave).count == 1)
  }

  @Test
  func unsubscribeStopsWaitingForServerCloseAfterTimeout() async throws {
    let h = Harness(timeout: .seconds(10))
    let channel = await h.client.channel("room")
    _ = try await h.subscribe(channel)

    let unsubscription = Task { await channel.unsubscribe() }
    _ = try #require(await h.received(ChannelEvent.leave))
    await h.clock.advance(by: .seconds(10))
    await unsubscription.value

    #expect(await channel.status == .unsubscribed)
    #expect(await channel.joinRef == nil)
  }

  /// `removeAllChannels()` must keep each channel routable until its `phx_close` arrives: a
  /// close for a topic no longer in `channels` is dropped, and the unsubscribe then waits for
  /// the whole timeout.
  @Test
  func removeAllChannelsDeliversEachServerClose() async throws {
    let h = Harness()
    let room = await h.client.channel("room")
    let lobby = await h.client.channel("lobby")
    let roomJoin = try await h.subscribe(room)
    let lobbyJoin = try await h.subscribe(lobby)

    let roomStatuses = await room.statusChanges()
    let lobbyStatuses = await lobby.statusChanges()
    let removal = Task { await h.client.removeAllChannels() }
    _ = try #require(await h.received(ChannelEvent.leave))
    _ = try #require(await h.received(ChannelEvent.leave))
    try h.close(roomJoin)
    try h.close(lobbyJoin)
    // Bounded on the wall clock: a dropped close leaves the unsubscribe waiting on the test
    // clock, and `removal.value` could not be cancelled, so check the statuses instead.
    try await withTimeout(.seconds(5)) {
      for await status in roomStatuses where status == .unsubscribed { break }
      for await status in lobbyStatuses where status == .unsubscribed { break }
    }
    await removal.value

    #expect(await h.client.channels.isEmpty)
    #expect(await h.client.status == .disconnected)
  }

  /// Issue #1145: with the socket gone, `phx_leave` could only be buffered into the next
  /// connection and `phx_close` never arrives, so unsubscribe neither sends nor waits.
  @Test
  func unsubscribeWithoutSocketSkipsLeave() async throws {
    let h = Harness()
    let channel = await h.client.channel("room")
    _ = try await h.subscribe(channel)
    await h.client.disconnect()

    await channel.unsubscribe()

    #expect(await channel.status == .unsubscribed)
    #expect(await h.client.sendBuffer.isEmpty)
    #expect(h.sent(ChannelEvent.leave).isEmpty)
  }

  @Test
  func unsubscribeWhileSubscribingCancelsTheSubscribe() async throws {
    let h = Harness()
    let channel = await h.client.channel("room")

    let subscription = Task { try await channel.subscribe() }
    _ = try #require(await h.received(ChannelEvent.join))
    await channel.unsubscribe()

    await #expect(throws: CancellationError.self) { try await subscription.value }
    #expect(await channel.status == .unsubscribed)
    #expect(h.sent(ChannelEvent.leave).count == 1)
  }

  // MARK: - Status stream

  @Test
  func statusChangesEmitsEveryTransition() async throws {
    let h = Harness()
    let channel = await h.client.channel("room")
    var statuses = await channel.statusChanges().makeAsyncIterator()

    let join = try await h.subscribe(channel)
    let unsubscription = Task { await channel.unsubscribe() }
    _ = try #require(await h.received(ChannelEvent.leave))
    try h.close(join)
    await unsubscription.value

    var trail: [RealtimeChannelStatus] = []
    for _ in 0..<5 {
      trail.append(try #require(await statuses.next()))
    }
    #expect(trail == [.unsubscribed, .subscribing, .subscribed, .unsubscribing, .unsubscribed])
  }

  @Test
  func removingTheChannelEndsItsStatusStream() async {
    let h = Harness()
    let channel = await h.client.channel("room")
    var statuses = await channel.statusChanges().makeAsyncIterator()
    #expect(await statuses.next() == .unsubscribed)

    await h.client.removeChannel(channel)

    #expect(await statuses.next() == nil)
  }

  @Test(.timeLimit(.minutes(1)))
  func joinConfirmedWhileThePhxJoinIsStillSendingCompletesTheSubscribe() async throws {
    let h = Harness()
    let channel = await h.client.channel("room")
    let statuses = await channel.statusChanges()
    let server = h.server
    // The join's send stays in flight until its reply has already subscribed the channel.
    h.socket.onSend { frame in
      guard case .text(let text) = frame,
        let join = try? RealtimeSerializer().decodeText(text), join.event == ChannelEvent.join,
        let reply = try? RealtimeSerializer().encodeText(
          RealtimeMessageV2(
            joinRef: join.ref, ref: join.ref, topic: join.topic, event: ChannelEvent.reply,
            payload: ["status": "ok", "response": ["postgres_changes": .array([])]]
          )
        )
      else { return }
      server.send(reply)
      for await status in statuses where status == .subscribed { break }
    }

    try await channel.subscribe()

    #expect(await channel.status == .subscribed)
    #expect(h.sent(ChannelEvent.join).count == 1)
  }

  // MARK: - Harness

  /// Parks one caller in `park()` until `open()`. Tests wait for `isParked` before acting.
  private final class Gate: Sendable {
    private let continuation = LockIsolated<CheckedContinuation<Void, Never>?>(nil)

    var isParked: Bool { continuation.value != nil }

    func park() async {
      await withCheckedContinuation { continuation.setValue($0) }
    }

    func open() {
      continuation.withValue {
        $0?.resume()
        $0 = nil
      }
    }
  }

  /// A client on a `TestClock`, connected to an in-memory server socket the test drives.
  private struct Harness {
    let clock: SignalingTestClock
    let socket: FakeWebSocket
    let server: FakeWebSocket
    let client: RealtimeClient
    let connects: LockIsolated<Int>

    /// `onConnect` runs inside each transport call and `onAccessToken` inside each access-token
    /// lookup, both numbered from 1, so a test can park one attempt at that point.
    init(
      timeout: Duration = RealtimeClientOptions.defaultTimeout,
      maxRetryAttempts: Int = 3,
      failedConnects: Int = 0,
      onConnect: @escaping @Sendable (_ attempt: Int) async -> Void = { _ in },
      onAccessToken: @escaping @Sendable (_ call: Int) async -> Void = { _ in }
    ) {
      let clock = SignalingTestClock()
      let (socket, server) = FakeWebSocket.fakes()
      let connects = LockIsolated(0)
      let accessTokenCalls = LockIsolated(0)
      self.clock = clock
      self.socket = socket
      self.server = server
      self.connects = connects
      client = RealtimeClient(
        url: URL(string: "http://localhost:54321/realtime/v1")!,
        options: RealtimeClientOptions(
          heartbeatInterval: .seconds(3600),
          timeout: timeout,
          maxRetryAttempts: maxRetryAttempts,
          accessToken: {
            let call = accessTokenCalls.withValue {
              $0 += 1
              return $0
            }
            await onAccessToken(call)
            return nil
          },
          handleAppLifecycle: false
        ),
        wsTransport: { _, _ in
          let attempt = connects.withValue {
            $0 += 1
            return $0
          }
          await onConnect(attempt)
          if attempt <= failedConnects {
            throw URLError(.notConnectedToInternet)
          }
          return socket
        },
        http: HTTPClient(transport: RecordingTransport()),
        clock: clock
      )
    }

    /// The next frame for `event` the server receives.
    func received(_ event: String) async -> RealtimeMessageV2? {
      for await frame in server.events {
        if let message = Self.decode(frame), message.event == event {
          return message
        }
      }
      return nil
    }

    /// Every frame for `event` the client has sent so far.
    func sent(_ event: String) -> [RealtimeMessageV2] {
      socket.sentEvents.compactMap(Self.decode).filter { $0.event == event }
    }

    /// Answers `join` the way the server does.
    func confirm(_ join: RealtimeMessageV2) throws {
      try reply(
        RealtimeMessageV2(
          joinRef: join.ref, ref: join.ref, topic: join.topic, event: ChannelEvent.reply,
          payload: ["status": "ok", "response": ["postgres_changes": .array([])]]
        )
      )
    }

    /// Closes the channel `join` opened, as the server does.
    func close(_ join: RealtimeMessageV2) throws {
      try reply(
        RealtimeMessageV2(
          joinRef: join.ref, ref: nil, topic: join.topic, event: ChannelEvent.close,
          payload: [:]
        )
      )
    }

    /// Subscribes `channel` and confirms its join. Returns the join.
    func subscribe(_ channel: RealtimeChannel) async throws -> RealtimeMessageV2 {
      async let subscription: Void = channel.subscribe()
      let join = try #require(await received(ChannelEvent.join))
      try confirm(join)
      try await subscription
      return join
    }

    private func reply(_ message: RealtimeMessageV2) throws {
      server.send(try RealtimeSerializer().encodeText(message))
    }

    private static func decode(_ frame: WebSocketEvent) -> RealtimeMessageV2? {
      guard case .frame(.text(let text)) = frame else { return nil }
      return try? RealtimeSerializer().decodeText(text)
    }
  }
}
