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
    let channel = h.client.channel("room")

    #expect(channel.status == .unsubscribed)
    #expect(await channel.joinRef == nil)
  }

  @Test
  func subscribeSendsJoinAndCompletesOnServerConfirmation() async throws {
    let h = Harness()
    let channel = h.client.channel("room")

    let join = try await h.subscribe(channel)

    #expect(channel.status == .subscribed)
    #expect(await channel.joinRef == join.ref)
    #expect(h.sent(ChannelEvent.join).count == 1)
  }

  @Test
  func subscribeWhileSubscribedIsNoOp() async throws {
    let h = Harness()
    let channel = h.client.channel("room")
    _ = try await h.subscribe(channel)

    try await channel.subscribe()

    #expect(h.sent(ChannelEvent.join).count == 1)
  }

  @Test(.timeLimit(.minutes(1)))
  func aCallerCancelledBeforeItJoinsTheSharedSubscribeThrowsAtOnce() async throws {
    let h = Harness()
    let channel = h.client.channel("room")

    let first = Task { try await channel.subscribe() }
    let join = try #require(await h.received(ChannelEvent.join))
    let second = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      try await channel.subscribe()
    }

    await #expect(throws: CancellationError.self) { try await second.value }
    try h.confirm(join)
    try await first.value
    #expect(channel.status == .subscribed)
  }

  @Test
  func concurrentSubscribesShareOneJoin() async throws {
    let h = Harness()
    let channel = h.client.channel("room")

    async let first: Void = channel.subscribe()
    async let second: Void = channel.subscribe()
    let join = try #require(await h.received(ChannelEvent.join))
    try h.confirm(join)

    try await first
    try await second
    #expect(channel.status == .subscribed)
    #expect(h.sent(ChannelEvent.join).count == 1)
  }

  @Test
  func subscribeRetriesAfterTimeoutThenSucceeds() async throws {
    let h = Harness(timeout: .seconds(10))
    let channel = h.client.channel("room")

    let subscription = Task { try await channel.subscribe() }
    let firstJoin = try #require(await h.received(ChannelEvent.join))
    // The attempt times out at 10s; the first retry waits 1s.
    await h.clock.advance(by: .seconds(11))
    let secondJoin = try #require(await h.received(ChannelEvent.join))
    try h.confirm(secondJoin)

    try await subscription.value
    #expect(channel.status == .subscribed)
    #expect(secondJoin.ref != firstJoin.ref)
    #expect(await channel.joinRef == secondJoin.ref)
  }

  @Test
  func requestTimeoutBoundsAJoinAttempt() async throws {
    let h = Harness(timeout: .seconds(3))
    let channel = h.client.channel("room")
    let statuses = channel.statusChanges()

    let subscription = Task { try await channel.subscribe() }
    defer { subscription.cancel() }
    _ = try #require(await withTimeout(.seconds(5)) { await h.received(ChannelEvent.join) })
    await h.clock.advance(by: .milliseconds(2900))
    guard case .subscribing = channel.status else {
      Issue.record("The join timed out before requestTimeout")
      return
    }
    await h.clock.advance(by: .milliseconds(100))

    let lastError = try await withTimeout(.seconds(5)) { () -> RealtimeError? in
      for await status in statuses {
        if case .resubscribing(_, _, let lastError) = status { return lastError }
      }
      return nil
    }
    #expect(lastError?.kind == .timeout)
  }

  /// Issue #1145 (defect 2): a transient socket connect failure must enter the retry ladder
  /// like a timeout instead of aborting the subscribe.
  @Test
  func subscribeRetriesWhenSocketConnectFailsTransiently() async throws {
    let h = Harness(failedConnects: 1)
    let channel = h.client.channel("room")
    var statuses = h.client.statusChanges().makeAsyncIterator()

    let subscription = Task { try await channel.subscribe() }
    #expect(await statuses.next() == .disconnected)
    #expect(await statuses.next() == .connecting)
    #expect(await statuses.next() == .disconnected)
    await h.clock.advance(by: .seconds(2))
    try h.confirm(try #require(await h.received(ChannelEvent.join)))

    try await subscription.value
    #expect(channel.status == .subscribed)
    #expect(h.connects.value == 2)
  }

  /// Connect failures keep the subscribe retrying on the rejoin steps; only the caller's own
  /// cancellation ends it.
  @Test(.timeLimit(.minutes(1)))
  func persistentConnectFailureKeepsRetryingUntilCancelled() async throws {
    let h = Harness(failedConnects: .max)
    let channel = h.client.channel("room")

    let subscription = Task { try await channel.subscribe() }
    #expect(await waitUntil { h.connects.value == 1 })
    for (step, connects) in [(1, 2), (2, 3), (5, 4), (10, 5), (10, 6)] {
      await h.clock.advance(by: .seconds(step))
      #expect(await waitUntil { h.connects.value == connects })
    }
    // Between attempts the channel reports the wait and why the last attempt failed.
    #expect(
      await waitUntil {
        guard case .resubscribing(6, .seconds(10), let lastError) = channel.status else {
          return false
        }
        return lastError.kind == .notConnected
      })
    subscription.cancel()

    await #expect(throws: CancellationError.self) { try await subscription.value }
    #expect(channel.status == .unsubscribed)
  }

  /// A subscribe waiting on a socket that never opens ends at once when its caller is cancelled.
  @Test(.timeLimit(.minutes(1)))
  func cancellingASubscribeWhileTheSocketNeverOpensThrowsAtOnce() async throws {
    let h = Harness(onConnect: { _ in try? await Task<Never, Never>.never() })
    let channel = h.client.channel("room")

    let subscription = Task { try await channel.subscribe() }
    #expect(await waitUntil { h.connects.value == 1 })
    subscription.cancel()

    await #expect(throws: CancellationError.self) { try await subscription.value }
    #expect(channel.status == .unsubscribed)
    #expect(h.client.status == .connecting)
  }

  @Test
  func joinCarriesThePostgresChangesOfOpenStreams() async throws {
    let h = Harness()
    let channel = h.client.channel("public:users")
    let inserts = channel.postgresChanges(event: .insert, table: "users")

    let subscription = Task { try await channel.subscribe() }
    let join = try #require(await h.received(ChannelEvent.join))
    let changes = join.payload["config"]?.objectValue?["postgres_changes"]?.arrayValue
    #expect(changes?.count == 1)
    #expect(changes?.first?.objectValue?["table"]?.stringValue == "users")
    // The `system` confirmation path: "Subscribed to PostgreSQL" confirms the join on its own.
    await h.client.apply(
      .frame(
        RealtimeMessage(
          joinRef: join.ref, ref: nil, topic: channel.wireTopic, event: ChannelEvent.system,
          payload: ["status": "ok", "extension": "postgres_changes"]
        )))

    try await subscription.value
    #expect(channel.status == .subscribed)
    withExtendedLifetime(inserts) {}
  }

  // MARK: - Late Postgres changes bindings

  @Test(.timeLimit(.minutes(1)))
  func lateBindingRejoinsAndEmitsResubscribed() async throws {
    let h = Harness(timeout: Self.noJoinTimeout)
    let channel = h.client.channel("room")
    let first = try await h.subscribe(channel)
    let events = LockIsolated<[RealtimeChannelEvent]>([])
    let stream = channel.events()
    let collector = Task { for await event in stream { events.withValue { $0.append(event) } } }
    defer { collector.cancel() }

    let changes = channel.postgresChanges(table: "t")

    let leave = try #require(await h.received(ChannelEvent.leave))
    #expect(leave.joinRef == first.ref)
    let rejoin = try #require(await h.received(ChannelEvent.join))
    let bindings = rejoin.payload["config"]?.objectValue?["postgres_changes"]?.arrayValue
    #expect(bindings?.count == 1)
    try h.confirm(rejoin)
    try h.send(Self.system(rejoin, status: "ok", extension: "postgres_changes"))

    #expect(await waitUntil { channel.status == .subscribed })
    #expect(await waitUntil { events.value == [.resubscribed, .postgresChangesReady] })
    withExtendedLifetime(changes) {}
  }

  @Test(.timeLimit(.minutes(1)))
  func twoLateBindingsRejoinWithoutUnsubscribing() async throws {
    let h = Harness(timeout: Self.noJoinTimeout)
    let channel = h.client.channel("room")
    _ = try await h.subscribe(channel)
    let statuses = LockIsolated<[RealtimeChannelStatus]>([])
    let stream = channel.statusChanges()
    let collector = Task { for await status in stream { statuses.withValue { $0.append(status) } } }
    defer { collector.cancel() }

    let first = channel.postgresChanges(table: "a")
    let second = channel.postgresChanges(table: "b")

    // Each rejoin carries every open binding; the last one carries both.
    var rejoin = try #require(await h.received(ChannelEvent.join))
    while true {
      try h.confirm(rejoin)
      try h.send(Self.system(rejoin, status: "ok", extension: "postgres_changes"))
      let bindings = rejoin.payload["config"]?.objectValue?["postgres_changes"]?.arrayValue
      if bindings?.count == 2 { break }
      rejoin = try #require(await h.received(ChannelEvent.join))
    }

    #expect(await waitUntil { channel.status == .subscribed })
    #expect(h.sent(ChannelEvent.join).count <= 3)
    #expect(!statuses.value.contains { if case .unsubscribed = $0 { true } else { false } })
    withExtendedLifetime((first, second)) {}
  }

  @Test(.timeLimit(.minutes(1)))
  func bindingAddedWhileSubscribingRejoinsAfterConfirm() async throws {
    let h = Harness(timeout: Self.noJoinTimeout)
    let channel = h.client.channel("room")

    let subscription = Task { try await channel.subscribe() }
    let join = try #require(await h.received(ChannelEvent.join))
    let changes = channel.postgresChanges(table: "t")
    try h.confirm(join)
    try await subscription.value

    #expect(try #require(await h.received(ChannelEvent.leave)).joinRef == join.ref)
    let rejoin = try #require(await h.received(ChannelEvent.join))
    #expect(rejoin.payload["config"]?.objectValue?["postgres_changes"]?.arrayValue?.count == 1)
    try h.confirm(rejoin)
    try h.send(Self.system(rejoin, status: "ok", extension: "postgres_changes"))
    #expect(await waitUntil { channel.status == .subscribed })
    #expect(h.sent(ChannelEvent.join).count == 2)
    withExtendedLifetime(changes) {}
  }

  @Test(.timeLimit(.minutes(1)))
  func staleCloseAfterRebindIsIgnored() async throws {
    let h = Harness(timeout: Self.noJoinTimeout)
    let channel = h.client.channel("room")
    let first = try await h.subscribe(channel)

    let changes = channel.postgresChanges(table: "t")
    let rejoin = try #require(await h.received(ChannelEvent.join))
    // The server closes the old join after the `phx_leave`.
    try h.close(first)
    try h.confirm(rejoin)
    try h.send(Self.system(rejoin, status: "ok", extension: "postgres_changes"))

    #expect(await waitUntil { channel.status == .subscribed })
    #expect(await channel.joinRef == rejoin.ref)
    withExtendedLifetime(changes) {}
  }

  @Test(.timeLimit(.minutes(1)))
  func unsubscribeDuringRebindStopsIt() async throws {
    let h = Harness(timeout: Self.noJoinTimeout)
    let channel = h.client.channel("room")
    _ = try await h.subscribe(channel)

    let changes = channel.postgresChanges(table: "t")
    let rejoin = try #require(await h.received(ChannelEvent.join))
    await channel.unsubscribe()
    try h.confirm(rejoin)
    try h.send(Self.system(rejoin, status: "ok", extension: "postgres_changes"))

    #expect(channel.status == .unsubscribed)
    #expect(h.sent(ChannelEvent.join).count == 2)
    withExtendedLifetime(changes) {}
  }

  @Test(.timeLimit(.minutes(1)))
  func cancellingAStreamDoesNotRejoin() async throws {
    let h = Harness(timeout: Self.noJoinTimeout)
    let channel = h.client.channel("room")
    let kept = channel.postgresChanges(table: "a")
    let dropped = channel.postgresChanges(table: "b")
    let consumer = Task { for await _ in dropped {} }

    let subscription = Task { try await channel.subscribe() }
    let join = try #require(await h.received(ChannelEvent.join))
    try h.confirm(join)
    try h.send(Self.system(join, status: "ok", extension: "postgres_changes"))
    try await subscription.value

    consumer.cancel()
    #expect(await waitUntil { channel.sinks.bindings.count == 1 })
    _ = channel.broadcasts(event: "x")

    #expect(channel.status == .subscribed)
    #expect(h.sent(ChannelEvent.join).count == 1)
    #expect(h.sent(ChannelEvent.leave).isEmpty)
    withExtendedLifetime(kept) {}
  }

  // MARK: - Postgres changes readiness

  @Test
  func subscribeWaitsForPostgresChangesReady() async throws {
    let h = Harness(timeout: Self.noJoinTimeout)
    let channel = h.client.channel("room")
    let changes = channel.postgresChanges(table: "t")

    let subscription = Task { try await channel.subscribe() }
    let join = try #require(await h.received(ChannelEvent.join))
    try h.confirm(join)
    #expect(await waitUntil { await channel.joinStage == .postgres })
    #expect(!channel.status.isSubscribed)

    try h.send(Self.system(join, status: "ok", extension: "postgres_changes"))

    try await subscription.value
    #expect(channel.status == .subscribed)
    withExtendedLifetime(changes) {}
  }

  @Test
  func postgresChangesFailureThrowsAndLeaves() async throws {
    let h = Harness(timeout: Self.noJoinTimeout)
    let channel = h.client.channel("room")
    let changes = channel.postgresChanges(table: "t")

    let subscription = Task { try await channel.subscribe() }
    let join = try #require(await h.received(ChannelEvent.join))
    try h.confirm(join)
    try h.send(
      Self.system(join, status: "error", extension: "postgres_changes", message: "boom"))

    let error = await #expect(throws: RealtimeError.self) { try await subscription.value }
    #expect(error?.kind == .server)
    #expect(error?.message.contains("boom") == true)
    #expect(error?.isRetryable == false)
    let leave = try #require(await h.received(ChannelEvent.leave))
    #expect(leave.joinRef == join.ref)
    #expect(channel.status.error != nil)
    #expect(await channel.joinRef == nil)
    #expect(h.sent(ChannelEvent.join).count == 1)
    withExtendedLifetime(changes) {}
  }

  @Test
  func postgresChangesTimeoutThrowsAndLeaves() async throws {
    let h = Harness(timeout: Self.noJoinTimeout)
    let channel = h.client.channel("room") {
      $0.postgresChanges.subscriptionTimeout = .seconds(5)
    }
    let changes = channel.postgresChanges(table: "t")

    let subscription = Task { try await channel.subscribe() }
    let join = try #require(await h.received(ChannelEvent.join))
    try h.confirm(join)
    #expect(await waitUntil { await channel.joinStage == .postgres })
    await h.clock.advance(by: .seconds(5))

    let error = await #expect(throws: RealtimeError.self) { try await subscription.value }
    #expect(error?.kind == .timeout)
    #expect(error?.isRetryable == false)
    #expect(try #require(await h.received(ChannelEvent.leave)).joinRef == join.ref)
    #expect(channel.status.error != nil)
    withExtendedLifetime(changes) {}
  }

  @Test
  func replicationReadyDoesNotConfirmThePostgresChangesWait() async throws {
    let h = Harness(timeout: Self.noJoinTimeout)
    let channel = h.client.channel("room")
    let changes = channel.postgresChanges(table: "t")

    let subscription = Task { try await channel.subscribe() }
    let join = try #require(await h.received(ChannelEvent.join))
    try h.confirm(join)
    #expect(await waitUntil { await channel.joinStage == .postgres })
    // Delivered on the actor, so the checks below run after the channel handled it.
    await h.client.apply(.frame(Self.system(join, status: "ok", extension: "system")))
    #expect(!channel.status.isSubscribed)
    #expect(await channel.joinStage == .postgres)

    try h.send(Self.system(join, status: "ok", extension: "postgres_changes"))
    try await subscription.value
    #expect(channel.status == .subscribed)
    withExtendedLifetime(changes) {}
  }

  /// The server accepted the join, so a `subscribe()` cancelled while it waits for the Postgres
  /// changes leaves the topic instead of leaving the server-side join behind.
  @Test(.timeLimit(.minutes(1)))
  func cancellingTheReadinessWaitLeavesTheTopic() async throws {
    let h = Harness(timeout: Self.noJoinTimeout)
    let channel = h.client.channel("room")
    let changes = channel.postgresChanges(table: "t")

    let subscription = Task { try await channel.subscribe() }
    let join = try #require(await h.received(ChannelEvent.join))
    try h.confirm(join)
    #expect(await waitUntil { await channel.joinStage == .postgres })
    subscription.cancel()

    await #expect(throws: CancellationError.self) { try await subscription.value }
    #expect(try #require(await h.received(ChannelEvent.leave)).joinRef == join.ref)
    #expect(channel.status == .unsubscribed)
    #expect(await channel.joinRef == nil)
    withExtendedLifetime(changes) {}
  }

  /// "Subscribed to PostgreSQL" that lands as the readiness timeout fires: `subscribe()` either
  /// succeeds with the join live, or throws with the join gone. Never a thrown error on a channel
  /// that reports `.subscribed`.
  @Test(.timeLimit(.minutes(1)))
  func readyAtTheTimeoutEndsSubscribedOrFailedNeverBoth() async throws {
    for _ in 1...20 {
      let h = Harness(timeout: Self.noJoinTimeout)
      let channel = h.client.channel("room") {
        $0.postgresChanges.subscriptionTimeout = .seconds(5)
      }
      let changes = channel.postgresChanges(table: "t")

      let subscription = Task { try await channel.subscribe() }
      let join = try #require(await h.received(ChannelEvent.join))
      try h.confirm(join)
      #expect(await waitUntil { await channel.joinStage == .postgres })
      await h.clock.advance(by: .seconds(5))
      // Lands while the channel sends `phx_leave` for the timed-out join.
      _ = try #require(await h.received(ChannelEvent.leave))
      await h.client.apply(.frame(Self.system(join, status: "ok", extension: "postgres_changes")))

      let result = await subscription.result
      let status = channel.status
      let joinRef = await channel.joinRef
      switch result {
      case .success:
        #expect(status == .subscribed)
        #expect(joinRef == join.ref)
      case .failure:
        #expect(!status.isSubscribed)
        #expect(joinRef == nil)
      }
      withExtendedLifetime(changes) {}
    }
  }

  @Test
  func postgresChangesReadyBeforeTheWaitParksStillSubscribes() async throws {
    let h = Harness(timeout: Self.noJoinTimeout)
    let channel = h.client.channel("room")
    let changes = channel.postgresChanges(table: "t")

    let subscription = Task { try await channel.subscribe() }
    let join = try #require(await h.received(ChannelEvent.join))
    try h.confirm(join)
    try h.send(Self.system(join, status: "ok", extension: "postgres_changes"))

    try await subscription.value
    #expect(channel.status == .subscribed)
    withExtendedLifetime(changes) {}
  }

  @Test
  func subscribeWithoutPostgresChangesIgnoresTheReadyWait() async throws {
    let h = Harness(timeout: Self.noJoinTimeout)
    let channel = h.client.channel("room")

    _ = try await h.subscribe(channel)

    #expect(channel.status == .subscribed)
  }

  @Test
  func waitForSubscriptionSendsOptionsAndSubscribesOnTheReply() async throws {
    let h = Harness(timeout: .seconds(10))
    let channel = h.client.channel("room") {
      $0.postgresChanges.waitForSubscription = true
      $0.postgresChanges.subscriptionTimeout = .seconds(15)
    }
    let changes = channel.postgresChanges(table: "t")

    let subscription = Task { try await channel.subscribe() }
    let join = try #require(await h.received(ChannelEvent.join))
    let options = join.payload["config"]?.objectValue?["postgres_changes_options"]
    #expect(options == ["wait": true, "timeout": 15000])
    // The server holds the reply while it sets up the bindings: past the 10 s client timeout,
    // the join is still waiting.
    await h.clock.advance(by: .seconds(11))
    #expect(h.sent(ChannelEvent.join).count == 1)
    try h.confirm(join)

    try await subscription.value
    #expect(channel.status == .subscribed)
    withExtendedLifetime(changes) {}
  }

  @Test
  func serverSideSubscribeTimeoutFailsWithoutRetry() async throws {
    let h = Harness(timeout: Self.noJoinTimeout)
    let channel = h.client.channel("room") {
      $0.postgresChanges.waitForSubscription = true
    }
    let changes = channel.postgresChanges(table: "t")

    let subscription = Task { try await channel.subscribe() }
    let join = try #require(await h.received(ChannelEvent.join))
    try h.fail(join, reason: "PostgresChangesSubscribeTimeout: Timed out after 15000ms")

    let error = await #expect(throws: RealtimeError.self) { try await subscription.value }
    #expect(error?.serverCode == .postgresChangesSubscribeTimeout)
    #expect(h.sent(ChannelEvent.join).count == 1)
    #expect(channel.status.error != nil)
    withExtendedLifetime(changes) {}
  }

  private static func system(
    _ join: RealtimeMessage, status: String, extension: String, message: String = ""
  ) -> RealtimeMessage {
    RealtimeMessage(
      joinRef: join.ref, ref: nil, topic: join.topic, event: ChannelEvent.system,
      payload: [
        "status": .string(status), "extension": .string(`extension`),
        "message": .string(message),
      ]
    )
  }

  // MARK: - Join errors

  @Test(.timeLimit(.minutes(1)))
  func fatalJoinErrorThrowsAtOnce() async throws {
    let h = Harness()
    let channel = h.client.channel("room")
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
    #expect(channel.status == .failed)
    #expect(channel.status.error?.kind == error?.kind)
    #expect(await channel.joinRef == nil)
    #expect(h.sent(ChannelEvent.join).count == 1)
  }

  @Test(.timeLimit(.minutes(1)))
  func transientJoinErrorRejoinsAfterThePolicyDelay() async throws {
    let h = Harness()
    let channel = h.client.channel("room")

    let subscription = Task { try await channel.subscribe() }
    let firstJoin = try #require(await h.received(ChannelEvent.join))
    try h.fail(firstJoin, reason: "RealtimeRestarting: Realtime is restarting, please standby")
    await h.clock.advance(by: .milliseconds(999))
    #expect(h.sent(ChannelEvent.join).count == 1)
    await h.clock.advance(by: .milliseconds(1))
    let secondJoin = try #require(await h.received(ChannelEvent.join))
    try h.confirm(secondJoin)

    try await subscription.value
    #expect(channel.status == .subscribed)
    #expect(await channel.joinRef == secondJoin.ref)
  }

  /// There is no attempt limit: transient errors keep the channel rejoining on the 1/2/5/10 s
  /// steps, and the last step repeats.
  @Test(.timeLimit(.minutes(1)))
  func transientJoinErrorsKeepRejoiningOnTheSteps() async throws {
    let h = Harness(timeout: Self.noJoinTimeout)
    let channel = h.client.channel("room")

    let subscription = Task { try await channel.subscribe() }
    var join = try #require(await h.received(ChannelEvent.join))
    for step in [1, 2, 5, 10, 10] {
      try h.fail(join, reason: "UnknownErrorOnChannel: boom")
      await h.clock.advance(by: .seconds(step))
      join = try #require(await h.received(ChannelEvent.join))
    }
    try h.confirm(join)

    try await subscription.value
    #expect(channel.status == .subscribed)
    #expect(h.sent(ChannelEvent.join).count == 6)
  }

  @Test(.timeLimit(.minutes(1)))
  func expiredTokenRejoinsOnceAtOnceWithAFreshToken() async throws {
    let h = Harness()
    let channel = h.client.channel("room")
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
    let channel = h.client.channel("room")
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
    #expect(channel.status == .subscribed)
    #expect(h.sent(ChannelEvent.join).count == 4)
  }

  @Test(.timeLimit(.minutes(1)))
  func rateLimitedJoinBacksOffForTheLongInterval() async throws {
    let h = Harness(timeout: Self.noJoinTimeout)
    let channel = h.client.channel("room")

    let subscription = Task { try await channel.subscribe() }
    let firstJoin = try #require(await h.received(ChannelEvent.join))
    try h.fail(firstJoin, reason: "ClientJoinRateLimitReached: Too many joins per second")
    await h.clock.advance(by: .seconds(29))
    #expect(h.sent(ChannelEvent.join).count == 1)
    await h.clock.advance(by: .seconds(1))
    try h.confirm(try #require(await h.received(ChannelEvent.join)))

    try await subscription.value
    #expect(channel.status == .subscribed)
  }

  /// Issue #1378: once a join timed out and the channel rejoined, a late success for the old
  /// join must not settle the new one.
  @Test(.timeLimit(.minutes(1)))
  func lateSuccessForAnEarlierJoinDoesNotSettleTheCurrentOne() async throws {
    let h = Harness(timeout: .seconds(10))
    let channel = h.client.channel("room")

    let subscription = Task { try await channel.subscribe() }
    let firstJoin = try #require(await h.received(ChannelEvent.join))
    await h.clock.advance(by: .seconds(11))
    let secondJoin = try #require(await h.received(ChannelEvent.join))
    try h.confirm(firstJoin)
    try h.fail(secondJoin, reason: "Unauthorized: denied")

    let error = await #expect(throws: RealtimeError.self) { try await subscription.value }
    #expect(error?.kind == .unauthorized)
    #expect(channel.status == .failed)
    #expect(channel.status.error?.kind == error?.kind)
  }

  @Test(.timeLimit(.minutes(1)))
  func lateErrorForAnEarlierJoinDoesNotFailTheCurrentOne() async throws {
    let h = Harness(timeout: .seconds(10))
    let channel = h.client.channel("room")

    let subscription = Task { try await channel.subscribe() }
    let firstJoin = try #require(await h.received(ChannelEvent.join))
    await h.clock.advance(by: .seconds(11))
    let secondJoin = try #require(await h.received(ChannelEvent.join))
    try h.fail(firstJoin, reason: "Unauthorized: denied")
    try h.confirm(secondJoin)

    try await subscription.value
    #expect(channel.status == .subscribed)
    #expect(await channel.joinRef == secondJoin.ref)
  }

  @Test(.timeLimit(.minutes(1)))
  func joinErrorWhileThePhxJoinIsStillSendingFailsTheSubscribe() async throws {
    let h = Harness()
    let channel = h.client.channel("room")
    let server = h.server
    // The join's send stays in flight until the channel has taken the error reply.
    h.socket.onSend { frame in
      guard case .text(let text) = frame,
        let join = try? RealtimeSerializer().decodeText(text), join.event == ChannelEvent.join,
        let reply = try? RealtimeSerializer().encodeText(
          RealtimeMessage(
            joinRef: join.ref, ref: join.ref, topic: join.topic, event: ChannelEvent.reply,
            payload: ["status": "error", "response": ["reason": "Unauthorized: denied"]]
          )
        )
      else { return }
      server.send(reply)
      await waitUntil {
        if case .failed = channel.status { true } else { false }
      }
    }

    let error = await #expect(throws: RealtimeError.self) { try await channel.subscribe() }
    #expect(error?.kind == .unauthorized)
    #expect(h.sent(ChannelEvent.join).count == 1)
  }

  @Test(.timeLimit(.minutes(1)))
  func refusedUpgradeThrowsAtOnce() async throws {
    let h = Harness(
      failedConnects: .max, connectError: RealtimeError.upgradeFailed(status: 401))
    let channel = h.client.channel("room")

    let error = await #expect(throws: RealtimeError.self) { try await channel.subscribe() }
    #expect(error?.kind == .transport)
    #expect(error?.isRetryable == false)
    #expect(h.connects.value == 1)
    #expect(channel.status == .failed)
    #expect(channel.status.error?.kind == error?.kind)
  }

  @Test(.timeLimit(.minutes(1)))
  func subscribeWithoutAConnectionThrowsAtOnceWhenConnectOnSubscribeIsOff() async throws {
    let h = Harness(connectOnSubscribe: false)
    let channel = h.client.channel("room")

    let error = await #expect(throws: RealtimeError.self) { try await channel.subscribe() }
    #expect(error?.kind == .notConnected)
    #expect(error?.isRetryable == false)
    #expect(h.connects.value == 0)
    #expect(channel.status == .failed)
    #expect(channel.status.error?.kind == error?.kind)
  }

  /// A join error with no reason is not one the classifier knows, so the channel rejoins.
  @Test(.timeLimit(.minutes(1)))
  func joinErrorWithoutAReasonRejoinsAfterThePolicyDelay() async throws {
    let h = Harness()
    let channel = h.client.channel("room")

    let subscription = Task { try await channel.subscribe() }
    let firstJoin = try #require(await h.received(ChannelEvent.join))
    try h.send(
      RealtimeMessage(
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
    let channel = h.client.channel("room")

    let subscription = Task { try await channel.subscribe() }
    let join = try #require(await h.received(ChannelEvent.join))
    try h.send(
      RealtimeMessage(
        joinRef: join.ref, ref: join.ref, topic: join.topic, event: ChannelEvent.reply,
        payload: ["status": "ok", "response": [:]]
      )
    )

    try await subscription.value
    #expect(channel.status == .subscribed)
    #expect(h.sent(ChannelEvent.join).count == 1)
  }

  /// A late `ok` for a join that timed out confirms it, so the backoff must not send another join.
  @Test(.timeLimit(.minutes(1)))
  func lateOkDuringTheBackoffSettlesTheSubscribeWithoutAnotherJoin() async throws {
    let h = Harness()
    let channel = h.client.channel("room")

    let subscription = Task { try await channel.subscribe() }
    let join = try #require(await h.received(ChannelEvent.join))
    await h.clock.advance(by: RealtimeClientOptions.defaultRequestTimeout)
    try h.confirm(join)
    #expect(await waitUntil { channel.status == .subscribed })
    await h.clock.advance(by: .seconds(1))

    try await subscription.value
    #expect(channel.status == .subscribed)
    #expect(h.sent(ChannelEvent.join).count == 1)
  }

  @Test(.timeLimit(.minutes(1)))
  func disconnectStopsASubscribeThatIsRetrying() async throws {
    let h = Harness(failedConnects: .max)
    let channel = h.client.channel("room")
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
    #expect(channel.status == .unsubscribed)
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
    let channel = h.client.channel("room")
    let finished = LockIsolated(false)

    let subscription = Task {
      defer { finished.setValue(true) }
      try await channel.subscribe()
    }
    let join = try #require(await h.received(ChannelEvent.join))
    try h.fail(join, reason: "UnknownErrorOnChannel: boom")
    h.server.close(code: nil, reason: "dropped")
    #expect(await waitUntil { h.client.status == .reconnecting })
    await h.clock.advance(by: .seconds(1))
    await h.clock.advance(by: .seconds(2))

    #expect(!finished.value)
    let status = channel.status
    #expect(status == .subscribing || status == .resubscribing)
    subscription.cancel()
    await h.client.disconnect()
  }

  /// Retrying cannot fix a join reply the client cannot read, so the subscribe fails at once.
  @Test(.timeLimit(.minutes(1)))
  func unreadableOkJoinReplyFailsTheSubscribeAtOnce() async throws {
    let h = Harness()
    let channel = h.client.channel("room")
    let start = h.clock.now

    let subscription = Task { try await channel.subscribe() }
    let join = try #require(await h.received(ChannelEvent.join))
    try h.send(
      RealtimeMessage(
        joinRef: join.ref, ref: join.ref, topic: join.topic, event: ChannelEvent.reply,
        payload: ["status": "ok", "response": ["postgres_changes": "not-an-array"]]
      )
    )

    let error = await #expect(throws: RealtimeError.self) { try await subscription.value }
    #expect(error?.isRetryable == false)
    #expect(channel.status == .failed)
    #expect(channel.status.error?.kind == error?.kind)
    #expect(h.clock.now == start)
    #expect(h.sent(ChannelEvent.join).count == 1)
  }

  /// Without an attempt limit, a channel that outlives its client must not retry forever.
  @Test(.timeLimit(.minutes(1)))
  func subscribeAfterTheClientIsReleasedThrowsAtOnce() async throws {
    func makeChannel() async -> RealtimeChannel {
      let client = RealtimeClient(
        url: URL(string: "http://localhost:54321/realtime/v1")!,
        options: RealtimeClientOptions(handleAppLifecycle: false)
      )
      return client.channel("room")
    }
    let channel = await makeChannel()
    try #require(await waitUntil { channel.client == nil })

    let error = await #expect(throws: RealtimeError.self) { try await channel.subscribe() }
    #expect(error?.kind == .notConnected)
    #expect(error?.isRetryable == false)
    #expect(channel.status == .unsubscribed)
  }

  /// A failed postgres-changes subscription arrives as a `system` error after the join. The
  /// join itself stands, so the channel stays subscribed and `events()` reports the failure.
  @Test
  func systemErrorLeavesTheChannelSubscribed() async throws {
    let h = Harness()
    let channel = h.client.channel("room")
    var events = channel.events().makeAsyncIterator()
    let join = try await h.subscribe(channel)

    try h.send(
      RealtimeMessage(
        joinRef: join.ref, ref: nil, topic: join.topic, event: ChannelEvent.system,
        payload: [
          "status": "error", "extension": "postgres_changes", "channel": "room",
          "message": "Unable to subscribe to changes with given parameters.",
        ]
      )
    )

    #expect(
      await events.next()
        == .postgresChangesFailed("Unable to subscribe to changes with given parameters."))
    #expect(channel.status == .subscribed)
    #expect(await channel.joinRef == join.ref)
  }

  // MARK: - Status values and channel events

  /// A join that times out reports the wait and the timeout, then the next attempt's number.
  @Test(.timeLimit(.minutes(1)))
  func statusReportsTheAttemptAndTheWaitBetweenAttempts() async throws {
    let h = Harness(timeout: .seconds(10))
    let channel = h.client.channel("room")
    let statuses = LockIsolated<[RealtimeChannelStatus]>([])
    let stream = channel.statusChanges()
    let collector = Task {
      for await status in stream { statuses.withValue { $0.append(status) } }
    }
    defer { collector.cancel() }

    let subscription = Task { try await channel.subscribe() }
    _ = try #require(await h.received(ChannelEvent.join))
    await h.clock.advance(by: .seconds(10))
    #expect(await waitUntil { statuses.value.contains(.resubscribing) })
    await h.clock.advance(by: .seconds(1))
    try h.confirm(try #require(await h.received(ChannelEvent.join)))
    try await subscription.value
    #expect(await waitUntil { statuses.value.last == .subscribed })

    let trail = statuses.value
    #expect(trail == [.unsubscribed, .subscribing, .resubscribing, .subscribing, .subscribed])
    guard case .subscribing(1) = trail[1], case .subscribing(2) = trail[3],
      case .resubscribing(1, .seconds(1), let lastError) = trail[2]
    else {
      Issue.record("Unexpected status values: \(trail)")
      return
    }
    #expect(lastError.kind == .timeout)
    #expect(trail[2].error?.kind == .timeout)
    #expect(trail[4].isSubscribed)
  }

  /// A failed channel starts over on the next `subscribe()`.
  @Test(.timeLimit(.minutes(1)))
  func subscribeAfterAFailureStartsOver() async throws {
    let h = Harness()
    let channel = h.client.channel("room")

    let first = Task { try await channel.subscribe() }
    try h.fail(try #require(await h.received(ChannelEvent.join)), reason: "Unauthorized: denied")
    await #expect(throws: RealtimeError.self) { try await first.value }
    #expect(channel.status.error?.kind == .unauthorized)

    _ = try await h.subscribe(channel)

    #expect(channel.status.isSubscribed)
    #expect(channel.status.error == nil)
  }

  @Test(.timeLimit(.minutes(1)))
  func unsubscribeClearsAFailure() async throws {
    let h = Harness()
    let channel = h.client.channel("room")
    let subscription = Task { try await channel.subscribe() }
    try h.fail(try #require(await h.received(ChannelEvent.join)), reason: "Unauthorized: denied")
    await #expect(throws: RealtimeError.self) { try await subscription.value }

    await channel.unsubscribe()

    #expect(channel.status == .unsubscribed)
  }

  // MARK: - Cancellation and server close

  @Test
  func cancellingSubscribeLeavesChannelUnsubscribed() async throws {
    let h = Harness()
    let channel = h.client.channel("room")

    let subscription = Task { try await channel.subscribe() }
    _ = try #require(await h.received(ChannelEvent.join))
    subscription.cancel()

    await #expect(throws: CancellationError.self) { try await subscription.value }
    #expect(channel.status == .unsubscribed)
    #expect(await channel.joinRef == nil)
  }

  /// A server close that aborts an in-flight subscribe surfaces as `channelClosedByServer`:
  /// never as `CancellationError`, which callers attribute to their own task.
  @Test
  func serverCloseDuringSubscribeThrowsChannelClosedByServer() async throws {
    let h = Harness()
    let channel = h.client.channel("room")

    let subscription = Task { try await channel.subscribe() }
    let join = try #require(await h.received(ChannelEvent.join))
    try h.close(join)

    let error = await #expect(throws: RealtimeError.self) { try await subscription.value }
    #expect(error?.kind == .channelClosedByServer)
    #expect(channel.status == .failed)
    #expect(channel.status.error?.kind == error?.kind)
  }

  // MARK: - Reconnect

  // MARK: - Unsubscribe

  @Test
  func unsubscribeWhenUnsubscribedIsNoOp() async {
    let h = Harness()
    let channel = h.client.channel("room")

    await channel.unsubscribe()

    #expect(channel.status == .unsubscribed)
    #expect(h.sent(ChannelEvent.leave).isEmpty)
  }

  @Test
  func unsubscribeSendsLeaveAndWaitsForServerClose() async throws {
    let h = Harness()
    let channel = h.client.channel("room")
    let join = try await h.subscribe(channel)

    let unsubscription = Task { await channel.unsubscribe() }
    _ = try #require(await h.received(ChannelEvent.leave))
    try h.close(join)
    await unsubscription.value

    #expect(channel.status == .unsubscribed)
    #expect(await channel.joinRef == nil)
    #expect(h.sent(ChannelEvent.leave).count == 1)
  }

  @Test
  func unsubscribeStopsWaitingForServerCloseAfterTimeout() async throws {
    let h = Harness(timeout: .seconds(10))
    let channel = h.client.channel("room")
    _ = try await h.subscribe(channel)

    let unsubscription = Task { await channel.unsubscribe() }
    _ = try #require(await h.received(ChannelEvent.leave))
    await h.clock.advance(by: .seconds(10))
    await unsubscription.value

    #expect(channel.status == .unsubscribed)
    #expect(await channel.joinRef == nil)
  }

  /// `removeAllChannels()` must keep each channel routable until its `phx_close` arrives: a
  /// close for a topic no longer in `channels` is dropped, and the unsubscribe then waits for
  /// the whole timeout.
  @Test
  func removeAllChannelsDeliversEachServerClose() async throws {
    let h = Harness()
    let room = h.client.channel("room")
    let lobby = h.client.channel("lobby")
    let roomJoin = try await h.subscribe(room)
    let lobbyJoin = try await h.subscribe(lobby)

    let roomStatuses = room.statusChanges()
    let lobbyStatuses = lobby.statusChanges()
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

    #expect(h.client.channels.isEmpty)
    #expect(h.client.status == .disconnected)
  }

  @Test
  func unsubscribeWhileSubscribingCancelsTheSubscribe() async throws {
    let h = Harness()
    let channel = h.client.channel("room")

    let subscription = Task { try await channel.subscribe() }
    _ = try #require(await h.received(ChannelEvent.join))
    await channel.unsubscribe()

    await #expect(throws: CancellationError.self) { try await subscription.value }
    #expect(channel.status == .unsubscribed)
    #expect(h.sent(ChannelEvent.leave).count == 1)
  }

  // MARK: - Status stream

  @Test
  func statusChangesEmitsEveryTransition() async throws {
    let h = Harness()
    let channel = h.client.channel("room")
    var statuses = channel.statusChanges().makeAsyncIterator()

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
    let channel = h.client.channel("room")
    var statuses = channel.statusChanges().makeAsyncIterator()
    #expect(await statuses.next() == .unsubscribed)

    await h.client.removeChannel(channel)

    #expect(await statuses.next() == nil)
  }

  @Test(.timeLimit(.minutes(1)))
  func joinConfirmedWhileThePhxJoinIsStillSendingCompletesTheSubscribe() async throws {
    let h = Harness()
    let channel = h.client.channel("room")
    let statuses = channel.statusChanges()
    let server = h.server
    // The join's send stays in flight until its reply has already subscribed the channel.
    h.socket.onSend { frame in
      guard case .text(let text) = frame,
        let join = try? RealtimeSerializer().decodeText(text), join.event == ChannelEvent.join,
        let reply = try? RealtimeSerializer().encodeText(
          RealtimeMessage(
            joinRef: join.ref, ref: join.ref, topic: join.topic, event: ChannelEvent.reply,
            payload: ["status": "ok", "response": ["postgres_changes": .array([])]]
          )
        )
      else { return }
      server.send(reply)
      for await status in statuses where status == .subscribed { break }
    }

    try await channel.subscribe()

    #expect(channel.status == .subscribed)
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
      timeout: Duration = RealtimeClientOptions.defaultRequestTimeout,
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
          requestTimeout: timeout,
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
    func received(_ event: String) async -> RealtimeMessage? {
      for await frame in server.events {
        if let message = Self.decode(frame), message.event == event {
          return message
        }
      }
      return nil
    }

    /// Every frame for `event` the client has sent so far.
    func sent(_ event: String) -> [RealtimeMessage] {
      socket.sentEvents.compactMap(Self.decode).filter { $0.event == event }
    }

    /// Answers `join` the way the server does.
    func confirm(_ join: RealtimeMessage) throws {
      try reply(
        RealtimeMessage(
          joinRef: join.ref, ref: join.ref, topic: join.topic, event: ChannelEvent.reply,
          payload: ["status": "ok", "response": ["postgres_changes": .array([])]]
        )
      )
    }

    /// Refuses `join` with `reason`, as the server does.
    func fail(_ join: RealtimeMessage, reason: String) throws {
      try reply(
        RealtimeMessage(
          joinRef: join.ref, ref: join.ref, topic: join.topic, event: ChannelEvent.reply,
          payload: ["status": "error", "response": ["reason": .string(reason)]]
        )
      )
    }

    /// Closes the channel `join` opened, as the server does.
    func close(_ join: RealtimeMessage) throws {
      try reply(
        RealtimeMessage(
          joinRef: join.ref, ref: nil, topic: join.topic, event: ChannelEvent.close,
          payload: [:]
        )
      )
    }

    /// Subscribes `channel` and confirms its join. Returns the join.
    func subscribe(_ channel: RealtimeChannel) async throws -> RealtimeMessage {
      async let subscription: Void = channel.subscribe()
      let join = try #require(await received(ChannelEvent.join))
      try confirm(join)
      try await subscription
      return join
    }

    /// Sends `message` from the server.
    func send(_ message: RealtimeMessage) throws {
      server.send(try RealtimeSerializer().encodeText(message))
    }

    private func reply(_ message: RealtimeMessage) throws {
      try send(message)
    }

    private static func decode(_ frame: WebSocketEvent) -> RealtimeMessage? {
      guard case .frame(.text(let text)) = frame else { return nil }
      return try? RealtimeSerializer().decodeText(text)
    }
  }
}
