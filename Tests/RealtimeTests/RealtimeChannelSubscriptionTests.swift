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
    let h = Harness(
      maxRetryAttempts: 1,
      onAccessToken: { call in
        if call == 1 { await gate.park() }
      })
    let channel = await h.client.channel("room")

    let firstSubscribe = Task { try await channel.subscribe() }
    #expect(await waitUntil { gate.isParked })

    await channel.resetForReconnect()
    let secondSubscribe = Task { try await channel.subscribe() }
    let secondJoin = try #require(await h.received(ChannelEvent.join))
    #expect(await channel.joinRef == secondJoin.ref)

    gate.open()
    await #expect(throws: (any Error).self) { try await firstSubscribe.value }

    try #require(await channel.status == .subscribing)
    #expect(await channel.joinRef == secondJoin.ref)
    #expect(h.sent(ChannelEvent.join).count == 1)

    try h.confirm(secondJoin)
    try await secondSubscribe.value
    #expect(await channel.status == .subscribed)
    #expect(h.sent(ChannelEvent.join).count == 1)
  }

  /// A server close that cancels a subscribe still surfaces as `channelClosedByServer` to that
  /// caller when a newer attempt has replaced it by the time it fails.
  @Test(.timeLimit(.minutes(1)))
  func serverCloseDuringStaleSubscribeStillSurfacesTypedError() async throws {
    let gate = Gate()
    let h = Harness(
      maxRetryAttempts: 1,
      onAccessToken: { call in
        if call == 1 { await gate.park() }
      })
    let channel = await h.client.channel("room")

    let firstSubscribe = Task { try await channel.subscribe() }
    #expect(await waitUntil { gate.isParked })
    #expect(await channel.didReceiveClose())

    let secondSubscribe = Task { try await channel.subscribe() }
    let secondJoin = try #require(await h.received(ChannelEvent.join))

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

  /// A reset ends an unsubscribe that waits for the server's `phx_close` (it died with the
  /// socket) and reports that the channel must not rejoin.
  @Test
  func resetEndsPendingUnsubscribeWithoutRejoin() async throws {
    let h = Harness(timeout: .seconds(10))
    let channel = await h.client.channel("room")
    _ = try await h.subscribe(channel)

    let unsubscription = Task { await channel.unsubscribe() }
    _ = try #require(await h.received(ChannelEvent.leave))
    #expect(await channel.resetForReconnect() == false)
    await unsubscription.value

    #expect(await channel.status == .unsubscribed)
    #expect(await channel.joinRef == nil)
    #expect(await channel.resetForReconnect() == false)
  }

  /// A reset asks to rejoin a channel the caller still wants, and again once the caller
  /// subscribes a channel it had unsubscribed.
  @Test
  func resetRejoinsUntilTheCallerUnsubscribes() async throws {
    let h = Harness(timeout: .seconds(10))
    let channel = await h.client.channel("room")
    _ = try await h.subscribe(channel)
    #expect(await channel.resetForReconnect() == true)

    // A server close would also unmap the channel, so let the unsubscribe time out instead.
    _ = try await h.subscribe(channel)
    let unsubscription = Task { await channel.unsubscribe() }
    _ = try #require(await h.received(ChannelEvent.leave))
    await h.clock.advance(by: .seconds(10))
    await unsubscription.value
    #expect(await channel.resetForReconnect() == false)

    _ = try await h.subscribe(channel)
    #expect(await channel.resetForReconnect() == true)
  }

  /// `removeChannel(_:)` stops a join still in flight. Unmapped, the channel would never see its
  /// reply and would keep retrying the join, and the server closes the topic's next channel on
  /// each duplicate join.
  @Test(.timeLimit(.minutes(1)))
  func removeChannelStopsAJoinInFlight() async throws {
    let h = Harness(timeout: .seconds(10), maxRetryAttempts: 3)
    // Keeps the client from disconnecting once the topic's channel is removed.
    _ = await h.client.channel("other")
    let channel = await h.client.channel("room")

    let subscription = Task { try await channel.subscribe() }
    _ = try #require(await h.received(ChannelEvent.join))
    await h.client.removeChannel(channel)

    #expect(await channel.status == .unsubscribed)
    #expect(await h.client.channels[channel.topic] == nil)
    // Past the attempt's timeout and the first retry delay.
    await h.clock.advance(by: .seconds(12))
    #expect(h.sent(ChannelEvent.join).count == 1)

    subscription.cancel()
    await #expect(throws: (any Error).self) { try await subscription.value }
  }

  /// A removal woken by a reconnect's reset stops the rejoin. The reset and the start of the
  /// rejoin's join share one turn of the channel, so the removal finds the join in flight, not an
  /// `.unsubscribed` channel whose rejoin is still to come and would join it once unmapped.
  @Test(.timeLimit(.minutes(1)))
  func removalAfterTheResetStopsTheRejoin() async throws {
    let h = Harness(timeout: .seconds(10), maxRetryAttempts: 3)
    // Keeps the client from disconnecting once the topic's channel is removed.
    _ = await h.client.channel("other")
    let channel = await h.client.channel("room")
    _ = try await h.subscribe(channel)

    let statuses = await channel.statusChanges()
    let rejoin = Task { try await channel.rejoinAfterReconnect() }
    for await status in statuses where status == .unsubscribed { break }
    #expect(await channel.status == .subscribing)
    await h.client.removeChannel(channel)

    #expect(await channel.status == .unsubscribed)
    #expect(await h.client.channels[channel.topic] == nil)
    await #expect(throws: (any Error).self) { try await rejoin.value }
    // Past the attempt's timeout and the first retry delay: at most the rejoin's first join.
    await h.clock.advance(by: .seconds(12))
    #expect(h.sent(ChannelEvent.join).count <= 2)
  }

  /// A reconnect joins only the channels the caller subscribed. A channel it only created may not
  /// have opened its postgres-change or presence streams yet, so that join would be incomplete.
  @Test(.timeLimit(.minutes(1)))
  func reconnectRejoinsOnlyTheChannelsTheCallerSubscribed() async throws {
    let h = Harness()
    let subscribed = await h.client.channel("room")
    let idle = await h.client.channel("lobby")
    _ = try await h.subscribe(subscribed)

    let rejoin = Task { await h.client.rejoinChannels() }
    let join = try #require(await h.received(ChannelEvent.join))
    #expect(join.topic == subscribed.topic)
    try h.confirm(join)
    try #require(await finishes(rejoin))

    #expect(await subscribed.status == .subscribed)
    #expect(await idle.status == .unsubscribed)
    #expect(h.sent(ChannelEvent.join).filter { $0.topic == idle.topic }.isEmpty)
  }

  /// `removeChannel(_:)` marks the channel removed even when it is already `.unsubscribed`, e.g.
  /// after its subscribe gave up during an outage. A reconnect that captured the channel before
  /// the removal must not join it once it is unmapped.
  @Test(.timeLimit(.minutes(1)))
  func removedChannelDoesNotRejoinAfterItsSubscribeGaveUp() async throws {
    let h = Harness(timeout: .seconds(10), maxRetryAttempts: 1)
    // Keeps the client from disconnecting once the topic's channel is removed.
    _ = await h.client.channel("other")
    let channel = await h.client.channel("room")
    let subscription = Task { try await channel.subscribe() }
    _ = try #require(await h.received(ChannelEvent.join))
    await h.clock.advance(by: .seconds(10))
    let error = await #expect(throws: RealtimeError.self) { try await subscription.value }
    #expect(error?.kind == .maxRetryAttemptsReached)

    await h.client.removeChannel(channel)
    // The step of a reconnect's `rejoinChannels()` that captured the channel before the removal.
    // A join of the unmapped channel would wait for a reply that never comes.
    let rejoin = Task { try await channel.rejoinAfterReconnect() }
    try #require(await finishes(rejoin))

    #expect(await channel.status == .unsubscribed)
    #expect(h.sent(ChannelEvent.join).count == 1)
  }

  /// A channel the server closed is unmapped, so it never joins again: neither through a
  /// reconnect's rejoin nor through a later `subscribe()`.
  @Test(.timeLimit(.minutes(1)))
  func channelClosedByTheServerNeverJoinsAgain() async throws {
    let h = Harness()
    let channel = await h.client.channel("room")
    let join = try await h.subscribe(channel)
    try h.close(join)
    #expect(await waitUntil { await h.client.channels[channel.topic] == nil })

    // A join of the unmapped channel would wait for a reply that never comes.
    let rejoin = Task { try await channel.rejoinAfterReconnect() }
    try #require(await finishes(rejoin))
    let subscription = Task { try await channel.subscribe() }
    try #require(await finishes(subscription))
    await #expect(throws: CancellationError.self) { try await subscription.value }

    #expect(await channel.status == .unsubscribed)
    #expect(h.sent(ChannelEvent.join).count == 1)
  }

  /// A `subscribe()` that waits on an in-flight unsubscribe must not join once a removal that
  /// waited on the same unsubscribe has unmapped the channel, whichever of the two resumes first.
  @Test(.timeLimit(.minutes(1)))
  func subscribeWaitingOnAnUnsubscribeDoesNotJoinARemovedChannel() async throws {
    let h = Harness(timeout: .seconds(10))
    // Keeps the client from disconnecting once the topic's channel is removed.
    _ = await h.client.channel("other")
    let channel = await h.client.channel("room")
    _ = try await h.subscribe(channel)

    let unsubscription = Task { await channel.unsubscribe() }
    _ = try #require(await h.received(ChannelEvent.leave))
    let subscription = Task { try await channel.subscribe() }
    #expect(await waitUntil { await channel.subscribeRequested })
    let removal = Task { await h.client.removeChannel(channel) }
    #expect(await waitUntil { await channel.isRemoved })
    // The unsubscribe stops waiting for `phx_close`; the subscribe and the removal resume.
    await h.clock.advance(by: .seconds(10))
    await unsubscription.value
    await removal.value

    // A join on the unmapped channel would wait for a reply that never comes.
    try #require(await finishes(subscription))
    await #expect(throws: CancellationError.self) { try await subscription.value }
    #expect(await channel.status == .unsubscribed)
    #expect(await h.client.channels[channel.topic] == nil)
    #expect(h.sent(ChannelEvent.join).count == 1)
  }

  /// An unsubscribe that a reset ended while it waited for `phx_close` must leave a newer
  /// unsubscribe alone when it resumes: the newer one owns the state and `joinRef`, and still
  /// waits for its own `phx_close`.
  @Test(.timeLimit(.minutes(1)))
  func staleUnsubscribeLeavesTheNewerUnsubscribeAlone() async throws {
    let h = Harness(timeout: .seconds(10))
    let channel = await h.client.channel("room")
    _ = try await h.subscribe(channel)
    let older = Task { await channel.unsubscribe() }
    _ = try #require(await h.received(ChannelEvent.leave))
    #expect(await waitUntil { await channel.closeWaiter != nil })

    let newer = await channel.resetAndStartNewerUnsubscribe(joinRef: "newer-join")
    await older.value

    #expect(await channel.status == .unsubscribing)
    #expect(await channel.joinRef == "newer-join")
    let leave = try #require(await h.received(ChannelEvent.leave))
    #expect(leave.joinRef == "newer-join")
    #expect(await channel.didReceiveClose(joinRef: "newer-join"))
    try #require(await finishes(newer))
    #expect(await channel.status == .unsubscribed)
  }

  /// An unsubscribe that a reset ended before it sent `phx_leave` must neither leave the newer
  /// join nor park on the newer unsubscribe's `phx_close`: taking that waiter would leave the
  /// newer unsubscribe unable to end.
  @Test(.timeLimit(.minutes(1)))
  func staleUnsubscribeDoesNotTakeTheNewerUnsubscribesCloseWaiter() async throws {
    let h = Harness(timeout: .seconds(10))
    let channel = await h.client.channel("room")
    _ = try await h.subscribe(channel)

    let (older, newer) = await channel.startUnsubscribeThenResetAndStartNewer(
      joinRef: "newer-join")
    try #require(await finishes(older))

    #expect(await channel.status == .unsubscribing)
    #expect(await waitUntil { await channel.closeWaiter != nil })
    #expect(await channel.didReceiveClose(joinRef: "newer-join"))
    try #require(await finishes(newer))
    #expect(await channel.status == .unsubscribed)
    #expect(h.sent(ChannelEvent.leave).count == 1)
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

  // MARK: - Harness

  /// Whether `task` finishes within `timeout` of real time. A regression that strands the task
  /// then fails the test instead of hanging the run.
  private func finishes<Success, Failure>(
    _ task: Task<Success, Failure>, timeout: TimeInterval = 2
  ) async -> Bool {
    let finished = LockIsolated(false)
    Task {
      _ = await task.result
      finished.setValue(true)
    }
    return await waitUntil(timeout: timeout) { finished.value }
  }

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

    private static func decode(_ frame: LegacyWebSocketEvent) -> RealtimeMessageV2? {
      guard case .text(let text) = frame else { return nil }
      return try? RealtimeSerializer().decodeText(text)
    }
  }
}

extension RealtimeChannel {
  /// In one turn of the channel: a reconnect resets it, a newer subscribe is confirmed with
  /// `joinRef`, and a newer unsubscribe starts. An older unsubscribe run resumes only after this
  /// turn, so it always finds the newer one owning the state.
  fileprivate func resetAndStartNewerUnsubscribe(joinRef newJoinRef: String) -> Task<Void, Never> {
    resetForReconnect()
    // Stands in for a newer subscribe the server has confirmed.
    joinRef = newJoinRef
    setState(.subscribed)
    return startUnsubscribe(waitForServerClose: true)
  }

  /// Starts an unsubscribe and, in the same turn, ``resetAndStartNewerUnsubscribe(joinRef:)``:
  /// the older run first runs once the newer one owns the state.
  fileprivate func startUnsubscribeThenResetAndStartNewer(
    joinRef newJoinRef: String
  ) -> (older: Task<Void, Never>, newer: Task<Void, Never>) {
    let older = startUnsubscribe(waitForServerClose: true)
    return (older, resetAndStartNewerUnsubscribe(joinRef: newJoinRef))
  }
}
