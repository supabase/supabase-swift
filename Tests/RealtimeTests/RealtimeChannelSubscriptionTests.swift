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

  /// Cancelling a caller that joined an in-flight subscribe ends its wait at once and leaves the
  /// first caller's attempt running.
  @Test(.timeLimit(.minutes(1)))
  func cancellingASecondCallerLeavesTheSharedSubscribeRunning() async throws {
    let h = Harness()
    let channel = await h.client.channel("room")

    let first = Task { try await channel.subscribe() }
    let firstJoin = try #require(await h.received(ChannelEvent.join))
    let second = Task { try await channel.subscribe() }
    #expect(await waitUntil { await !channel.sharedSubscribeWaiters.isEmpty })
    second.cancel()

    await #expect(throws: CancellationError.self) { try await second.value }
    #expect(await channel.sharedSubscribeWaiters.isEmpty)
    #expect(await channel.status == .subscribing)
    try h.confirm(firstJoin)
    try await first.value
    #expect(await channel.status == .subscribed)
    #expect(h.sent(ChannelEvent.join).count == 1)
  }

  @Test(.timeLimit(.minutes(1)))
  func aCallerCancelledBeforeItJoinsTheSharedSubscribeThrowsAtOnce() async throws {
    let h = Harness()
    let channel = await h.client.channel("room")

    let first = Task { try await channel.subscribe() }
    let join = try #require(await h.received(ChannelEvent.join))
    let second = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      try await channel.subscribe()
    }

    await #expect(throws: CancellationError.self) { try await second.value }
    #expect(await channel.sharedSubscribeWaiters.isEmpty)
    try h.confirm(join)
    try await first.value
    #expect(await channel.status == .subscribed)
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
    let h = Harness(timeout: .seconds(10))
    let channel = await h.client.channel("room")

    let subscription = Task { try await channel.subscribe() }
    let firstJoin = try #require(await h.received(ChannelEvent.join))
    // The attempt times out at 10s; the first retry waits 1s.
    await h.clock.advance(by: .seconds(11))
    let secondJoin = try #require(await h.received(ChannelEvent.join))
    try h.confirm(secondJoin)

    try await subscription.value
    #expect(await channel.status == .subscribed)
    #expect(secondJoin.ref != firstJoin.ref)
    #expect(await channel.joinRef == secondJoin.ref)
  }

  /// Issue #1145 (defect 2): a transient socket connect failure must enter the retry ladder
  /// like a timeout instead of aborting the subscribe.
  @Test
  func subscribeRetriesWhenSocketConnectFailsTransiently() async throws {
    let h = Harness(failedConnects: 1)
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

  /// Connect failures keep the subscribe retrying on the rejoin steps; only the caller's own
  /// cancellation ends it.
  @Test(.timeLimit(.minutes(1)))
  func persistentConnectFailureKeepsRetryingUntilCancelled() async throws {
    let h = Harness(failedConnects: .max)
    let channel = await h.client.channel("room")

    let subscription = Task { try await channel.subscribe() }
    #expect(await waitUntil { h.connects.value == 1 })
    for (step, connects) in [(1, 2), (2, 3), (5, 4), (10, 5), (10, 6)] {
      await h.clock.advance(by: .seconds(step))
      #expect(await waitUntil { h.connects.value == connects })
    }
    #expect(await channel.status == .subscribing)
    subscription.cancel()

    await #expect(throws: CancellationError.self) { try await subscription.value }
    #expect(await channel.status == .unsubscribed)
  }

  /// A subscribe waiting on a socket that never opens ends at once when its caller is cancelled.
  @Test(.timeLimit(.minutes(1)))
  func cancellingASubscribeWhileTheSocketNeverOpensThrowsAtOnce() async throws {
    let h = Harness(onConnect: { _ in try? await Task<Never, Never>.never() })
    let channel = await h.client.channel("room")

    let subscription = Task { try await channel.subscribe() }
    #expect(await waitUntil { h.connects.value == 1 })
    subscription.cancel()

    await #expect(throws: CancellationError.self) { try await subscription.value }
    #expect(await channel.status == .unsubscribed)
    #expect(await h.client.status == .connecting)
  }

  @Test
  func joinCarriesThePostgresChangesOfOpenStreams() async throws {
    let h = Harness()
    let channel = await h.client.channel("public:users")
    let inserts = await channel.postgresChanges(event: .insert, table: "users")

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

  // MARK: - Join errors

  @Test(.timeLimit(.minutes(1)))
  func fatalJoinErrorThrowsAtOnce() async throws {
    let h = Harness()
    let channel = await h.client.channel("room")
    let start = h.clock.now

    let subscription = Task { try await channel.subscribe() }
    let join = try #require(await h.received(ChannelEvent.join))
    try h.fail(
      join,
      reason: "Unauthorized: You do not have permissions to read from this Channel topic: room")

    let error = await #expect(throws: RealtimeError.self) { try await subscription.value }
    #expect(error?.kind == .unauthorized)
    #expect(error?.serverCode == .unauthorized)
    #expect(error?.isRetryable == false)
    #expect(h.clock.now == start)
    #expect(await channel.status == .unsubscribed)
    #expect(await channel.joinRef == nil)
    #expect(h.sent(ChannelEvent.join).count == 1)
  }

  @Test(.timeLimit(.minutes(1)))
  func transientJoinErrorRejoinsAfterThePolicyDelay() async throws {
    let h = Harness()
    let channel = await h.client.channel("room")

    let subscription = Task { try await channel.subscribe() }
    let firstJoin = try #require(await h.received(ChannelEvent.join))
    try h.fail(firstJoin, reason: "RealtimeRestarting: Realtime is restarting, please standby")
    await h.clock.advance(by: .milliseconds(999))
    #expect(h.sent(ChannelEvent.join).count == 1)
    await h.clock.advance(by: .milliseconds(1))
    let secondJoin = try #require(await h.received(ChannelEvent.join))
    try h.confirm(secondJoin)

    try await subscription.value
    #expect(await channel.status == .subscribed)
    #expect(await channel.joinRef == secondJoin.ref)
  }

  /// There is no attempt limit: transient errors keep the channel rejoining on the 1/2/5/10 s
  /// steps, and the last step repeats.
  @Test(.timeLimit(.minutes(1)))
  func transientJoinErrorsKeepRejoiningOnTheSteps() async throws {
    let h = Harness(timeout: Self.noJoinTimeout)
    let channel = await h.client.channel("room")

    let subscription = Task { try await channel.subscribe() }
    var join = try #require(await h.received(ChannelEvent.join))
    for step in [1, 2, 5, 10, 10] {
      try h.fail(join, reason: "UnknownErrorOnChannel: boom")
      await h.clock.advance(by: .seconds(step))
      join = try #require(await h.received(ChannelEvent.join))
    }
    try h.confirm(join)

    try await subscription.value
    #expect(await channel.status == .subscribed)
    #expect(h.sent(ChannelEvent.join).count == 6)
  }

  @Test(.timeLimit(.minutes(1)))
  func expiredTokenRejoinsOnceAtOnceWithAFreshToken() async throws {
    let h = Harness()
    let channel = await h.client.channel("room")
    let start = h.clock.now

    let subscription = Task { try await channel.subscribe() }
    let firstJoin = try #require(await h.received(ChannelEvent.join))
    try h.fail(firstJoin, reason: "InvalidJWTToken: Token has expired 3 seconds ago")
    let secondJoin = try #require(await h.received(ChannelEvent.join))
    #expect(secondJoin.payload["access_token"] != firstJoin.payload["access_token"])
    try h.fail(secondJoin, reason: "InvalidJWTToken: Token has expired 3 seconds ago")

    let error = await #expect(throws: RealtimeError.self) { try await subscription.value }
    #expect(error?.kind == .unauthorized)
    #expect(error?.serverCode == .invalidJWTToken)
    #expect(h.clock.now == start)
    #expect(h.sent(ChannelEvent.join).count == 2)
  }

  /// The one fresh-token rejoin is per run of expired-token errors: a token that expires again
  /// after other failures gets another one.
  @Test(.timeLimit(.minutes(1)))
  func aTokenThatExpiresAgainAfterOtherFailuresGetsAnotherRefresh() async throws {
    let h = Harness(timeout: Self.noJoinTimeout)
    let channel = await h.client.channel("room")
    let expired = "InvalidJWTToken: Token has expired 3 seconds ago"

    let subscription = Task { try await channel.subscribe() }
    var join = try #require(await h.received(ChannelEvent.join))
    try h.fail(join, reason: expired)
    join = try #require(await h.received(ChannelEvent.join))
    try h.fail(join, reason: "UnknownErrorOnChannel: boom")
    await h.clock.advance(by: .seconds(2))
    join = try #require(await h.received(ChannelEvent.join))
    try h.fail(join, reason: expired)
    join = try #require(await h.received(ChannelEvent.join))
    try h.confirm(join)

    try await subscription.value
    #expect(await channel.status == .subscribed)
    #expect(h.sent(ChannelEvent.join).count == 4)
  }

  @Test(.timeLimit(.minutes(1)))
  func rateLimitedJoinBacksOffForTheLongInterval() async throws {
    let h = Harness(timeout: Self.noJoinTimeout)
    let channel = await h.client.channel("room")

    let subscription = Task { try await channel.subscribe() }
    let firstJoin = try #require(await h.received(ChannelEvent.join))
    try h.fail(firstJoin, reason: "ClientJoinRateLimitReached: Too many joins per second")
    await h.clock.advance(by: .seconds(29))
    #expect(h.sent(ChannelEvent.join).count == 1)
    await h.clock.advance(by: .seconds(1))
    try h.confirm(try #require(await h.received(ChannelEvent.join)))

    try await subscription.value
    #expect(await channel.status == .subscribed)
  }

  /// Issue #1378: once a join timed out and the channel rejoined, a late success for the old
  /// join must not settle the new one.
  @Test(.timeLimit(.minutes(1)))
  func lateSuccessForAnEarlierJoinDoesNotSettleTheCurrentOne() async throws {
    let h = Harness(timeout: .seconds(10))
    let channel = await h.client.channel("room")

    let subscription = Task { try await channel.subscribe() }
    let firstJoin = try #require(await h.received(ChannelEvent.join))
    await h.clock.advance(by: .seconds(11))
    let secondJoin = try #require(await h.received(ChannelEvent.join))
    try h.confirm(firstJoin)
    try h.fail(secondJoin, reason: "Unauthorized: denied")

    let error = await #expect(throws: RealtimeError.self) { try await subscription.value }
    #expect(error?.kind == .unauthorized)
    #expect(await channel.status == .unsubscribed)
  }

  @Test(.timeLimit(.minutes(1)))
  func lateErrorForAnEarlierJoinDoesNotFailTheCurrentOne() async throws {
    let h = Harness(timeout: .seconds(10))
    let channel = await h.client.channel("room")

    let subscription = Task { try await channel.subscribe() }
    let firstJoin = try #require(await h.received(ChannelEvent.join))
    await h.clock.advance(by: .seconds(11))
    let secondJoin = try #require(await h.received(ChannelEvent.join))
    try h.fail(firstJoin, reason: "Unauthorized: denied")
    try h.confirm(secondJoin)

    try await subscription.value
    #expect(await channel.status == .subscribed)
    #expect(await channel.joinRef == secondJoin.ref)
  }

  @Test(.timeLimit(.minutes(1)))
  func joinErrorWhileThePhxJoinIsStillSendingFailsTheSubscribe() async throws {
    let h = Harness()
    let channel = await h.client.channel("room")
    let server = h.server
    // The join's send stays in flight until the channel has taken the error reply.
    h.socket.onSend { frame in
      guard case .text(let text) = frame,
        let join = try? RealtimeSerializer().decodeText(text), join.event == ChannelEvent.join,
        let reply = try? RealtimeSerializer().encodeText(
          RealtimeMessageV2(
            joinRef: join.ref, ref: join.ref, topic: join.topic, event: ChannelEvent.reply,
            payload: ["status": "error", "response": ["reason": "Unauthorized: denied"]]
          )
        )
      else { return }
      server.send(reply)
      await waitUntil { await channel.joinFailure != nil }
    }

    let error = await #expect(throws: RealtimeError.self) { try await channel.subscribe() }
    #expect(error?.kind == .unauthorized)
    #expect(await channel.joinFailure == nil)
    #expect(h.sent(ChannelEvent.join).count == 1)
  }

  @Test(.timeLimit(.minutes(1)))
  func refusedUpgradeThrowsAtOnce() async throws {
    let h = Harness(
      failedConnects: .max, connectError: RealtimeError.upgradeFailed(status: 401))
    let channel = await h.client.channel("room")

    let error = await #expect(throws: RealtimeError.self) { try await channel.subscribe() }
    #expect(error?.kind == .transport)
    #expect(error?.isRetryable == false)
    #expect(h.connects.value == 1)
    #expect(await channel.status == .unsubscribed)
  }

  @Test(.timeLimit(.minutes(1)))
  func subscribeWithoutAConnectionThrowsAtOnceWhenConnectOnSubscribeIsOff() async throws {
    let h = Harness(connectOnSubscribe: false)
    let channel = await h.client.channel("room")

    let error = await #expect(throws: RealtimeError.self) { try await channel.subscribe() }
    #expect(error?.kind == .notConnected)
    #expect(error?.isRetryable == false)
    #expect(h.connects.value == 0)
    #expect(await channel.status == .unsubscribed)
  }

  /// A join error with no reason is not one the classifier knows, so the channel rejoins.
  @Test(.timeLimit(.minutes(1)))
  func joinErrorWithoutAReasonRejoinsAfterThePolicyDelay() async throws {
    let h = Harness()
    let channel = await h.client.channel("room")

    let subscription = Task { try await channel.subscribe() }
    let firstJoin = try #require(await h.received(ChannelEvent.join))
    try h.send(
      RealtimeMessageV2(
        joinRef: firstJoin.ref, ref: firstJoin.ref, topic: firstJoin.topic,
        event: ChannelEvent.reply, payload: ["status": "error", "response": [:]]
      )
    )
    await h.clock.advance(by: .seconds(1))
    let secondJoin = try #require(await h.received(ChannelEvent.join))
    try h.confirm(secondJoin)

    try await subscription.value
    #expect(await channel.joinRef == secondJoin.ref)
  }

  @Test(.timeLimit(.minutes(1)))
  func okJoinReplyWithoutPostgresChangesConfirmsTheJoin() async throws {
    let h = Harness()
    let channel = await h.client.channel("room")

    let subscription = Task { try await channel.subscribe() }
    let join = try #require(await h.received(ChannelEvent.join))
    try h.send(
      RealtimeMessageV2(
        joinRef: join.ref, ref: join.ref, topic: join.topic, event: ChannelEvent.reply,
        payload: ["status": "ok", "response": [:]]
      )
    )

    try await subscription.value
    #expect(await channel.status == .subscribed)
    #expect(h.sent(ChannelEvent.join).count == 1)
  }

  /// A late `ok` for a join that timed out confirms it, so the backoff must not send another join.
  @Test(.timeLimit(.minutes(1)))
  func lateOkDuringTheBackoffSettlesTheSubscribeWithoutAnotherJoin() async throws {
    let h = Harness()
    let channel = await h.client.channel("room")

    let subscription = Task { try await channel.subscribe() }
    let join = try #require(await h.received(ChannelEvent.join))
    await h.clock.advance(by: RealtimeClientOptions.defaultTimeout)
    try h.confirm(join)
    #expect(await waitUntil { await channel.status == .subscribed })
    await h.clock.advance(by: .seconds(1))

    try await subscription.value
    #expect(await channel.status == .subscribed)
    #expect(h.sent(ChannelEvent.join).count == 1)
  }

  @Test(.timeLimit(.minutes(1)))
  func disconnectStopsASubscribeThatIsRetrying() async throws {
    let h = Harness(failedConnects: .max)
    let channel = await h.client.channel("room")
    let finished = LockIsolated(false)

    let subscription = Task {
      defer { finished.setValue(true) }
      try await channel.subscribe()
    }
    #expect(await waitUntil { h.connects.value == 1 })
    await h.client.disconnect()

    try #require(await waitUntil(timeout: 2) { finished.value })
    let error = await #expect(throws: RealtimeError.self) { try await subscription.value }
    #expect(error?.kind == .notConnected)
    #expect(await channel.status == .unsubscribed)
    await h.clock.advance(by: .seconds(10))
    #expect(h.connects.value == 1)
  }

  /// With `connectOnSubscribe` off, a socket that drops while the join retries is the client's to
  /// restore: the subscribe keeps retrying instead of failing.
  @Test(.timeLimit(.minutes(1)))
  func aDropWhileRetryingKeepsTheSubscribeGoingWhenConnectOnSubscribeIsOff() async throws {
    let h = Harness(
      connectOnSubscribe: false,
      onConnect: { attempt in
        if attempt > 1 { try? await Task.sleep(for: .seconds(3600)) }
      }
    )
    try await h.client.connect()
    let channel = await h.client.channel("room")
    let finished = LockIsolated(false)

    let subscription = Task {
      defer { finished.setValue(true) }
      try await channel.subscribe()
    }
    let join = try #require(await h.received(ChannelEvent.join))
    try h.fail(join, reason: "UnknownErrorOnChannel: boom")
    h.server.close(code: nil, reason: "dropped")
    #expect(await waitUntil { await h.client.status == .connecting })
    await h.clock.advance(by: .seconds(1))
    await h.clock.advance(by: .seconds(2))

    #expect(!finished.value)
    #expect(await channel.status == .subscribing)
    subscription.cancel()
    await h.client.disconnect()
  }

  /// Retrying cannot fix a join reply the client cannot read, so the subscribe fails at once.
  @Test(.timeLimit(.minutes(1)))
  func unreadableOkJoinReplyFailsTheSubscribeAtOnce() async throws {
    let h = Harness()
    let channel = await h.client.channel("room")
    let start = h.clock.now

    let subscription = Task { try await channel.subscribe() }
    let join = try #require(await h.received(ChannelEvent.join))
    try h.send(
      RealtimeMessageV2(
        joinRef: join.ref, ref: join.ref, topic: join.topic, event: ChannelEvent.reply,
        payload: ["status": "ok", "response": ["postgres_changes": "not-an-array"]]
      )
    )

    let error = await #expect(throws: RealtimeError.self) { try await subscription.value }
    #expect(error?.isRetryable == false)
    #expect(await channel.status == .unsubscribed)
    #expect(h.clock.now == start)
    #expect(h.sent(ChannelEvent.join).count == 1)
  }

  /// Every caller of a shared subscribe gets the same error when the server closes the channel.
  @Test(.timeLimit(.minutes(1)))
  func aServerCloseFailsEveryCallerWithChannelClosedByServer() async throws {
    let h = Harness()
    let channel = await h.client.channel("room")

    let first = Task { try await channel.subscribe() }
    let join = try #require(await h.received(ChannelEvent.join))
    let second = Task { try await channel.subscribe() }
    #expect(await waitUntil { await !channel.sharedSubscribeWaiters.isEmpty })
    try h.close(join)

    for caller in [first, second] {
      let error = await #expect(throws: RealtimeError.self) { try await caller.value }
      #expect(error?.kind == .channelClosedByServer)
    }
  }

  /// A rejoin that keeps failing must not keep a released client alive.
  @Test(.timeLimit(.minutes(1)))
  func aRejoinThatNeverSucceedsDoesNotRetainTheClient() async throws {
    final class WeakBox: @unchecked Sendable {
      weak var client: RealtimeClient?
    }
    let box = WeakBox()
    let (socket, server) = FakeWebSocket.fakes()

    func scope() async throws {
      let client = RealtimeClient(
        url: URL(string: "http://localhost:54321/realtime/v1")!,
        options: RealtimeClientOptions(
          heartbeatInterval: .seconds(3600),
          accessToken: { "token" },
          handleAppLifecycle: false
        ),
        wsTransport: { _, _ in socket },
        http: HTTPClient(transport: RecordingTransport()),
        clock: SignalingTestClock()
      )
      box.client = client
      try await client.connect()
      _ = await client.channel("room")
      Task { await client.rejoinChannels() }
      for await frame in server.events {
        if case .frame(.text(let text)) = frame, text.contains(ChannelEvent.join) { break }
      }
    }
    try await scope()

    #expect(await waitUntil(timeout: 5) { box.client == nil })
  }

  /// Without an attempt limit, a channel that outlives its client must not retry forever.
  @Test(.timeLimit(.minutes(1)))
  func subscribeAfterTheClientIsReleasedThrowsAtOnce() async throws {
    func makeChannel() async -> RealtimeChannel {
      let client = RealtimeClient(
        url: URL(string: "http://localhost:54321/realtime/v1")!,
        options: RealtimeClientOptions(handleAppLifecycle: false)
      )
      return await client.channel("room")
    }
    let channel = await makeChannel()
    try #require(await waitUntil { await channel.client == nil })

    let error = await #expect(throws: RealtimeError.self) { try await channel.subscribe() }
    #expect(error?.kind == .notConnected)
    #expect(error?.isRetryable == false)
    #expect(await channel.status == .unsubscribed)
  }

  /// A failed postgres-changes subscription arrives as a `system` error after the join. The
  /// join itself stands, so the channel stays subscribed and the system stream carries it.
  @Test
  func systemErrorLeavesTheChannelSubscribed() async throws {
    let h = Harness()
    let channel = await h.client.channel("room")
    var systemMessages = await channel.systemMessages().makeAsyncIterator()
    let join = try await h.subscribe(channel)

    try h.send(
      RealtimeMessageV2(
        joinRef: join.ref, ref: nil, topic: join.topic, event: ChannelEvent.system,
        payload: [
          "status": "error", "extension": "postgres_changes", "channel": "room",
          "message": "Unable to subscribe to changes with given parameters.",
        ]
      )
    )

    let message = try #require(await systemMessages.next())
    #expect(message.status == .error)
    #expect(await channel.status == .subscribed)
    #expect(await channel.joinRef == join.ref)
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
  /// never as `CancellationError`, which callers attribute to their own task.
  @Test
  func serverCloseDuringSubscribeThrowsChannelClosedByServer() async throws {
    let h = Harness()
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
    let h = Harness()
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
    let h = Harness()
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

  /// A join timeout no step of these tests reaches. With the default 10 s, a step of 10 s or
  /// more can fire the timeout before the channel handles the error reply the test sent.
  private static let noJoinTimeout: Duration = .seconds(3600)

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
      failedConnects: Int = 0,
      connectError: any Error = URLError(.notConnectedToInternet),
      connectOnSubscribe: Bool = true,
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
          connectOnSubscribe: connectOnSubscribe,
          accessToken: {
            let call = accessTokenCalls.withValue {
              $0 += 1
              return $0
            }
            await onAccessToken(call)
            return "token-\(call)"
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
            throw connectError
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

    /// Refuses `join` with `reason`, as the server does.
    func fail(_ join: RealtimeMessageV2, reason: String) throws {
      try reply(
        RealtimeMessageV2(
          joinRef: join.ref, ref: join.ref, topic: join.topic, event: ChannelEvent.reply,
          payload: ["status": "error", "response": ["reason": .string(reason)]]
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

    /// Sends `message` from the server.
    func send(_ message: RealtimeMessageV2) throws {
      server.send(try RealtimeSerializer().encodeText(message))
    }

    private func reply(_ message: RealtimeMessageV2) throws {
      try send(message)
    }

    private static func decode(_ frame: WebSocketEvent) -> RealtimeMessageV2? {
      guard case .frame(.text(let text)) = frame else { return nil }
      return try? RealtimeSerializer().decodeText(text)
    }
  }
}
