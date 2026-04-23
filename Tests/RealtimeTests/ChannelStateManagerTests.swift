import ConcurrencyExtras
import XCTest

@testable import Realtime

final class ChannelStateManagerTests: XCTestCase {
  /// Helper that returns a `ChannelStateManager` wired up with controllable
  /// fakes for every injected operation, plus spies so tests can assert what
  /// the state machine did.
  struct Harness: Sendable {
    let sut: ChannelStateManager
    let ref: LockIsolated<Int>
    let ensureConnected: LockIsolated<Bool>
    let joinCallCount: LockIsolated<Int>
    let lastJoinRef: LockIsolated<String?>
    let lastJoinChanges: LockIsolated<[PostgresJoinConfig]>
    let leaveCallCount: LockIsolated<Int>
  }

  private func makeHarness(
    timeoutInterval: TimeInterval = 0.2,
    maxRetryAttempts: Int = 3,
    retryDelay: @escaping @Sendable (Int) -> TimeInterval = { _ in 0.01 }
  ) -> Harness {
    let ref = LockIsolated<Int>(0)
    let ensureConnected = LockIsolated<Bool>(true)
    let joinCallCount = LockIsolated<Int>(0)
    let lastJoinRef = LockIsolated<String?>(nil)
    let lastJoinChanges = LockIsolated<[PostgresJoinConfig]>([])
    let leaveCallCount = LockIsolated<Int>(0)

    let sut = ChannelStateManager(
      topic: "test",
      logger: nil,
      maxRetryAttempts: maxRetryAttempts,
      timeoutInterval: timeoutInterval,
      makeRef: {
        ref.withValue { $0 += 1 }
        return "\(ref.value)"
      },
      ensureSocketConnected: { ensureConnected.value },
      joinOperation: { ref, changes in
        joinCallCount.withValue { $0 += 1 }
        lastJoinRef.setValue(ref)
        lastJoinChanges.setValue(changes)
      },
      leaveOperation: {
        leaveCallCount.withValue { $0 += 1 }
      },
      retryDelay: retryDelay
    )

    return Harness(
      sut: sut,
      ref: ref,
      ensureConnected: ensureConnected,
      joinCallCount: joinCallCount,
      lastJoinRef: lastJoinRef,
      lastJoinChanges: lastJoinChanges,
      leaveCallCount: leaveCallCount
    )
  }

  /// Schedules a task that waits for the state manager to push a `phx_join`
  /// (observable via the harness's `joinCallCount`) and then signals a
  /// successful subscription. Using a poll-then-confirm pattern avoids a race
  /// where the confirmation fires before `subscribe()` has transitioned into
  /// `.subscribing` and is therefore silently dropped.
  private func confirmSubscribeOnJoin(_ h: Harness) -> Task<Void, Never> {
    Task { [h] in
      while h.joinCallCount.value == 0 {
        try? await Task.sleep(nanoseconds: 5_000_000)
      }
      await h.sut.didReceiveSubscribedOK()
    }
  }

  // MARK: - Initial state

  func testInitialStateIsUnsubscribed() async {
    let h = makeHarness()
    let state = await h.sut.state
    guard case .unsubscribed = state else {
      return XCTFail("Expected .unsubscribed, got \(state)")
    }

    let joinRef = await h.sut.joinRef
    XCTAssertNil(joinRef)

    let changes = await h.sut.clientChanges
    XCTAssertTrue(changes.isEmpty)
  }

  // MARK: - Subscribe

  func testSubscribePushesJoinAndTransitionsOnConfirmation() async throws {
    let h = makeHarness()

    // Server-side confirmation arrives shortly after the join is pushed.
    let confirmer = Task { [h] in
      while h.joinCallCount.value == 0 {
        try? await Task.sleep(nanoseconds: 5_000_000)
      }
      await h.sut.didReceiveSubscribedOK()
    }

    try await h.sut.subscribe()

    _ = await confirmer.value

    let state = await h.sut.state
    guard case .subscribed = state else {
      return XCTFail("Expected .subscribed, got \(state)")
    }
    XCTAssertEqual(h.joinCallCount.value, 1)
    XCTAssertEqual(h.lastJoinRef.value, "1")
  }

  func testSubscribeWhileAlreadySubscribedIsNoOp() async throws {
    let h = makeHarness()

    let confirmer = confirmSubscribeOnJoin(h)
    try await h.sut.subscribe()
    _ = await confirmer.value

    try await h.sut.subscribe()

    XCTAssertEqual(h.joinCallCount.value, 1, "Second subscribe should be a no-op")
  }

  func testConcurrentSubscribesDedup() async throws {
    let h = makeHarness()

    async let first: Void = h.sut.subscribe()
    async let second: Void = h.sut.subscribe()

    // Trigger confirmation after both calls have entered the actor.
    try? await Task.sleep(nanoseconds: 20_000_000)
    await h.sut.didReceiveSubscribedOK()

    try await first
    try await second

    XCTAssertEqual(h.joinCallCount.value, 1, "Only one phx_join should be pushed")
  }

  func testSubscribeRetriesOnTimeoutThenSucceeds() async throws {
    let h = makeHarness(timeoutInterval: 0.05, maxRetryAttempts: 3)

    // Wait for the second join attempt before confirming.
    let confirmer = Task { [h] in
      while h.joinCallCount.value < 2 {
        try? await Task.sleep(nanoseconds: 5_000_000)
      }
      await h.sut.didReceiveSubscribedOK()
    }

    try await h.sut.subscribe()
    _ = await confirmer.value

    let state = await h.sut.state
    guard case .subscribed = state else {
      return XCTFail("Expected .subscribed, got \(state)")
    }
    XCTAssertGreaterThanOrEqual(h.joinCallCount.value, 2)
  }

  func testSubscribeThrowsAfterMaxRetries() async {
    let h = makeHarness(timeoutInterval: 0.05, maxRetryAttempts: 2)

    do {
      try await h.sut.subscribe()
      XCTFail("Expected subscribe to throw after max retries")
    } catch {
      XCTAssertTrue(error is RealtimeError)
    }

    let state = await h.sut.state
    guard case .unsubscribed = state else {
      return XCTFail("State should reset to .unsubscribed after failure, got \(state)")
    }
    XCTAssertEqual(h.joinCallCount.value, 2)
  }

  func testSubscribeFailsWhenSocketCannotConnect() async {
    let h = makeHarness(timeoutInterval: 0.2, maxRetryAttempts: 1)
    h.ensureConnected.setValue(false)

    do {
      try await h.sut.subscribe()
      XCTFail("Expected subscribe to throw when socket is not connected")
    } catch {
      // Expected
    }

    let state = await h.sut.state
    guard case .unsubscribed = state else {
      return XCTFail("Expected .unsubscribed, got \(state)")
    }
  }

  // MARK: - Unsubscribe

  func testUnsubscribeFromUnsubscribedIsNoOp() async {
    let h = makeHarness()
    await h.sut.unsubscribe()

    let state = await h.sut.state
    guard case .unsubscribed = state else {
      return XCTFail("Expected .unsubscribed, got \(state)")
    }
    XCTAssertEqual(h.leaveCallCount.value, 0)
  }

  func testUnsubscribeFromSubscribedPushesLeaveAndWaitsForClose() async throws {
    let h = makeHarness()

    let confirmer = confirmSubscribeOnJoin(h)
    try await h.sut.subscribe()
    _ = await confirmer.value

    await h.sut.unsubscribe()

    let state = await h.sut.state
    guard case .unsubscribed = state else {
      return XCTFail("Expected .unsubscribed, got \(state)")
    }
    XCTAssertEqual(h.leaveCallCount.value, 1)

    let joinRef = await h.sut.joinRef
    XCTAssertNil(joinRef, "joinRef should be cleared after phx_leave")
  }

  func testUnsubscribeWhileSubscribingCancelsSubscribe() async throws {
    let h = makeHarness(timeoutInterval: 5.0, maxRetryAttempts: 1)

    let subscribeTask = Task { try? await h.sut.subscribe() }

    // Wait until the subscribe attempt has pushed phx_join.
    while h.joinCallCount.value == 0 {
      try? await Task.sleep(nanoseconds: 5_000_000)
    }

    // Respond to the phx_leave with a close so unsubscribe can finish.
    let closer = Task { [h] in
      while h.leaveCallCount.value == 0 {
        try? await Task.sleep(nanoseconds: 5_000_000)
      }
      await h.sut.didReceiveClose()
    }

    await h.sut.unsubscribe()
    _ = await closer.value
    _ = await subscribeTask.value

    let state = await h.sut.state
    guard case .unsubscribed = state else {
      return XCTFail("Expected .unsubscribed, got \(state)")
    }
  }

  // MARK: - Server-close while subscribed

  func testDidReceiveCloseTransitionsToUnsubscribed() async throws {
    let h = makeHarness()

    let confirmer = confirmSubscribeOnJoin(h)
    try await h.sut.subscribe()
    _ = await confirmer.value

    await h.sut.didReceiveClose()

    let state = await h.sut.state
    guard case .unsubscribed = state else {
      return XCTFail("Expected .unsubscribed, got \(state)")
    }
    let joinRef = await h.sut.joinRef
    XCTAssertNil(joinRef)
  }

  // MARK: - State stream

  func testStateChangesEmitsTransitions() async throws {
    let h = makeHarness()

    let observerReady = expectation(description: "observer subscribed")
    let subscribingSeen = expectation(description: "subscribing observed")
    let subscribedSeen = expectation(description: "subscribed observed")
    let unsubscribingSeen = expectation(description: "unsubscribing observed")
    let unsubscribedAfterSubscribe = expectation(description: "unsubscribed observed (final)")

    let sawSubscribed = LockIsolated(false)
    let sawUnsubscribing = LockIsolated(false)
    let observerReadyFired = LockIsolated(false)
    let observer = Task { [h] in
      for await state in h.sut.stateChanges {
        if !observerReadyFired.value {
          observerReadyFired.setValue(true)
          observerReady.fulfill()
        }
        switch state {
        case .subscribing: subscribingSeen.fulfill()
        case .subscribed:
          if !sawSubscribed.value {
            sawSubscribed.setValue(true)
            subscribedSeen.fulfill()
          }
        case .unsubscribing:
          if !sawUnsubscribing.value {
            sawUnsubscribing.setValue(true)
            unsubscribingSeen.fulfill()
          }
        case .unsubscribed:
          if sawSubscribed.value {
            unsubscribedAfterSubscribe.fulfill()
            return
          }
        }
      }
    }

    // Wait for the observer to actually subscribe to the stream — otherwise
    // fast state transitions below can race ahead of it and the `.subscribing`
    // replay is missed.
    await fulfillment(of: [observerReady], timeout: 1)

    let confirmer = confirmSubscribeOnJoin(h)
    try await h.sut.subscribe()
    _ = await confirmer.value

    await h.sut.unsubscribe()

    await fulfillment(
      of: [subscribingSeen, subscribedSeen, unsubscribingSeen, unsubscribedAfterSubscribe],
      timeout: 2
    )
    observer.cancel()
  }

  // MARK: - Client changes & pushes

  func testAddClientChangeAppendsConfig() async {
    let h = makeHarness()
    let config1 = PostgresJoinConfig(event: .insert, schema: "public", table: "users", filter: nil)
    let config2 = PostgresJoinConfig(event: .update, schema: "public", table: "posts", filter: nil)

    await h.sut.addClientChange(config1)
    await h.sut.addClientChange(config2)

    let changes = await h.sut.clientChanges
    XCTAssertEqual(changes.count, 2)
    XCTAssertEqual(changes[0].table, "users")
    XCTAssertEqual(changes[1].table, "posts")
  }

  func testClientChangesAreForwardedToJoinOperation() async throws {
    let h = makeHarness()
    let config = PostgresJoinConfig(event: .insert, schema: "public", table: "users", filter: nil)
    await h.sut.addClientChange(config)

    // Poll-then-confirm avoids a race where an eager `didReceiveSubscribedOK`
    // runs before `subscribe()` has transitioned into `.subscribing` and is
    // therefore dropped by the guard in the state manager.
    let confirmer = Task { [h] in
      while h.joinCallCount.value == 0 {
        try? await Task.sleep(nanoseconds: 5_000_000)
      }
      await h.sut.didReceiveSubscribedOK()
    }
    try await h.sut.subscribe()
    _ = await confirmer.value

    XCTAssertEqual(h.lastJoinChanges.value.count, 1)
    XCTAssertEqual(h.lastJoinChanges.value.first?.table, "users")
  }

  @MainActor
  func testStorePushAndRemovePush() async {
    let h = makeHarness()
    let message = RealtimeMessageV2(
      joinRef: nil, ref: "r1", topic: "t", event: "e", payload: [:]
    )
    let push = PushV2(channel: nil, message: message)

    await h.sut.storePush(push, ref: "r1")
    let fetched = await h.sut.removePush(ref: "r1")
    XCTAssertTrue(fetched === push)

    let fetchedAgain = await h.sut.removePush(ref: "r1")
    XCTAssertNil(fetchedAgain)
  }

  @MainActor
  func testDidReceiveCloseClearsStoredPushes() async throws {
    let h = makeHarness()
    let confirmer = confirmSubscribeOnJoin(h)
    try await h.sut.subscribe()
    _ = await confirmer.value

    let message = RealtimeMessageV2(
      joinRef: nil, ref: "r1", topic: "t", event: "e", payload: [:]
    )
    let push = PushV2(channel: nil, message: message)
    await h.sut.storePush(push, ref: "r1")

    await h.sut.didReceiveClose()

    let fetched = await h.sut.removePush(ref: "r1")
    XCTAssertNil(fetched, "Pushes should be cleared after didReceiveClose")
  }
}
