import ConcurrencyExtras
import Foundation
import Testing

@testable import Realtime
@testable import RealtimeV2

@Suite
struct ChannelStateManagerTests {
  /// Helper that returns a `ChannelStateManager` wired up with controllable
  /// fakes for every injected operation, plus spies so tests can assert what
  /// the state machine did.
  struct Harness: Sendable {
    let sut: ChannelStateManager
    let ref: LockIsolated<Int>
    let ensureConnected: LockIsolated<Bool>
    let clientChanges: LockIsolated<[PostgresJoinConfig]>
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
    let clientChanges = LockIsolated<[PostgresJoinConfig]>([])
    let joinCallCount = LockIsolated<Int>(0)
    let lastJoinRef = LockIsolated<String?>(nil)
    let lastJoinChanges = LockIsolated<[PostgresJoinConfig]>([])
    let leaveCallCount = LockIsolated<Int>(0)

    let sut = ChannelStateManager(
      topic: "test",
      logger: nil,
      maxRetryAttempts: maxRetryAttempts,
      timeoutInterval: timeoutInterval,
      clock: ContinuousClock(),
      makeRef: {
        ref.withValue { $0 += 1 }
        return "\(ref.value)"
      },
      ensureSocketConnected: { ensureConnected.value },
      getClientChanges: { clientChanges.value },
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
      clientChanges: clientChanges,
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

  @Test
  func initialStateIsUnsubscribed() async {
    let h = makeHarness()
    let state = await h.sut.state
    guard case .unsubscribed = state else {
      Issue.record("Expected .unsubscribed, got \(state)")
      return
    }

    let joinRef = await h.sut.joinRef
    #expect(joinRef == nil)
  }

  // MARK: - Subscribe

  @Test
  func subscribePushesJoinAndTransitionsOnConfirmation() async throws {
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
      Issue.record("Expected .subscribed, got \(state)")
      return
    }
    #expect(h.joinCallCount.value == 1)
    #expect(h.lastJoinRef.value == "1")
  }

  @Test
  func subscribeWhileAlreadySubscribedIsNoOp() async throws {
    let h = makeHarness()

    let confirmer = confirmSubscribeOnJoin(h)
    try await h.sut.subscribe()
    _ = await confirmer.value

    try await h.sut.subscribe()

    #expect(h.joinCallCount.value == 1, "Second subscribe should be a no-op")
  }

  @Test
  func concurrentSubscribesDedup() async throws {
    let h = makeHarness()

    async let first: Void = h.sut.subscribe()
    async let second: Void = h.sut.subscribe()

    // Trigger confirmation after both calls have entered the actor.
    try? await Task.sleep(nanoseconds: 20_000_000)
    await h.sut.didReceiveSubscribedOK()

    try await first
    try await second

    #expect(h.joinCallCount.value == 1, "Only one phx_join should be pushed")
  }

  @Test
  func subscribeRetriesOnTimeoutThenSucceeds() async throws {
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
      Issue.record("Expected .subscribed, got \(state)")
      return
    }
    #expect(h.joinCallCount.value >= 2)
  }

  @Test
  func subscribeThrowsAfterMaxRetries() async {
    let h = makeHarness(timeoutInterval: 0.05, maxRetryAttempts: 2)

    do {
      try await h.sut.subscribe()
      Issue.record("Expected subscribe to throw after max retries")
    } catch {
      #expect(error is RealtimeError)
    }

    let state = await h.sut.state
    guard case .unsubscribed = state else {
      Issue.record("State should reset to .unsubscribed after failure, got \(state)")
      return
    }
    #expect(h.joinCallCount.value == 2)
  }

  @Test
  func subscribeFailsWhenSocketCannotConnect() async {
    let h = makeHarness(timeoutInterval: 0.2, maxRetryAttempts: 1)
    h.ensureConnected.setValue(false)

    do {
      try await h.sut.subscribe()
      Issue.record("Expected subscribe to throw when socket is not connected")
    } catch {
      // Expected
    }

    let state = await h.sut.state
    guard case .unsubscribed = state else {
      Issue.record("Expected .unsubscribed, got \(state)")
      return
    }
  }

  // MARK: - Unsubscribe

  @Test
  func unsubscribeFromUnsubscribedIsNoOp() async {
    let h = makeHarness()
    await h.sut.unsubscribe()

    let state = await h.sut.state
    guard case .unsubscribed = state else {
      Issue.record("Expected .unsubscribed, got \(state)")
      return
    }
    #expect(h.leaveCallCount.value == 0)
  }

  @Test
  func unsubscribeFromSubscribedPushesLeaveAndWaitsForClose() async throws {
    let h = makeHarness()

    let confirmer = confirmSubscribeOnJoin(h)
    try await h.sut.subscribe()
    _ = await confirmer.value

    await h.sut.unsubscribe()

    let state = await h.sut.state
    guard case .unsubscribed = state else {
      Issue.record("Expected .unsubscribed, got \(state)")
      return
    }
    #expect(h.leaveCallCount.value == 1)

    let joinRef = await h.sut.joinRef
    #expect(joinRef == nil, "joinRef should be cleared after phx_leave")
  }

  @Test
  func unsubscribeWhileSubscribingCancelsSubscribe() async throws {
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
      Issue.record("Expected .unsubscribed, got \(state)")
      return
    }
  }

  // MARK: - Server-close while subscribed

  @Test
  func didReceiveCloseTransitionsToUnsubscribed() async throws {
    let h = makeHarness()

    let confirmer = confirmSubscribeOnJoin(h)
    try await h.sut.subscribe()
    _ = await confirmer.value

    await h.sut.didReceiveClose()

    let state = await h.sut.state
    guard case .unsubscribed = state else {
      Issue.record("Expected .unsubscribed, got \(state)")
      return
    }
    let joinRef = await h.sut.joinRef
    #expect(joinRef == nil)
  }

  // MARK: - State stream

  @Test
  func stateChangesEmitsTransitions() async throws {
    let h = makeHarness()

    let observerReady = LockIsolated(false)
    let subscribingSeen = LockIsolated(false)
    let subscribedSeen = LockIsolated(false)
    let unsubscribingSeen = LockIsolated(false)
    let unsubscribedAfterSubscribe = LockIsolated(false)

    let sawSubscribed = LockIsolated(false)
    let sawUnsubscribing = LockIsolated(false)
    let observerReadyFired = LockIsolated(false)
    let observer = Task { [h] in
      for await state in h.sut.stateChanges {
        if !observerReadyFired.value {
          observerReadyFired.setValue(true)
          observerReady.setValue(true)
        }
        switch state {
        case .subscribing: subscribingSeen.setValue(true)
        case .subscribed:
          if !sawSubscribed.value {
            sawSubscribed.setValue(true)
            subscribedSeen.setValue(true)
          }
        case .unsubscribing:
          if !sawUnsubscribing.value {
            sawUnsubscribing.setValue(true)
            unsubscribingSeen.setValue(true)
          }
        case .unsubscribed:
          if sawSubscribed.value {
            unsubscribedAfterSubscribe.setValue(true)
            return
          }
        }
      }
    }

    // Wait for the observer to actually subscribe to the stream — otherwise
    // fast state transitions below can race ahead of it and the `.subscribing`
    // replay is missed.
    let becameReady = await waitUntil(timeout: 1) { observerReady.value }
    #expect(becameReady, "observer subscribed")

    let confirmer = confirmSubscribeOnJoin(h)
    try await h.sut.subscribe()
    _ = await confirmer.value

    await h.sut.unsubscribe()

    let sawAllTransitions = await waitUntil(timeout: 2) {
      subscribingSeen.value && subscribedSeen.value && unsubscribingSeen.value
        && unsubscribedAfterSubscribe.value
    }
    #expect(sawAllTransitions, "expected all state transitions to be observed")
    observer.cancel()
  }

  // MARK: - Client changes & pushes

  @Test
  func clientChangesAreForwardedToJoinOperation() async throws {
    let h = makeHarness()
    let config = PostgresJoinConfig(event: .insert, schema: "public", table: "users", filter: nil)
    // The channel owns the buffer — the actor reads it through the injected
    // `getClientChanges` closure when it builds the join payload.
    h.clientChanges.withValue { $0.append(config) }

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

    #expect(h.lastJoinChanges.value.count == 1)
    #expect(h.lastJoinChanges.value.first?.table == "users")
  }

  @Test
  @MainActor
  func storePushIfJoinRefMatchesStoresWhenJoinRefMatches() async throws {
    let h = makeHarness()
    let confirmer = confirmSubscribeOnJoin(h)
    try await h.sut.subscribe()
    _ = await confirmer.value

    let joinRef = await h.sut.joinRef
    let message = RealtimeMessageV2(
      joinRef: joinRef, ref: "r1", topic: "t", event: "e", payload: [:]
    )
    let push = PushV2(channel: nil, message: message)

    let stored = await h.sut.storePushIfJoinRefMatches(push, ref: "r1", joinRef: joinRef)
    #expect(stored)

    let fetched = await h.sut.removePush(ref: "r1")
    #expect(fetched === push)
  }

  @Test
  @MainActor
  func storePushIfJoinRefMatchesSkipsWhenJoinRefChanged() async throws {
    let h = makeHarness()
    let confirmer = confirmSubscribeOnJoin(h)
    try await h.sut.subscribe()
    _ = await confirmer.value

    // Caller snapshots joinRef…
    let staleJoinRef = await h.sut.joinRef

    // …then the channel closes before the caller registers the push.
    await h.sut.didReceiveClose()

    let message = RealtimeMessageV2(
      joinRef: staleJoinRef, ref: "r1", topic: "t", event: "e", payload: [:]
    )
    let push = PushV2(channel: nil, message: message)

    let stored = await h.sut.storePushIfJoinRefMatches(
      push, ref: "r1", joinRef: staleJoinRef
    )
    #expect(!stored, "Push from a stale join cycle must not be registered")

    let fetched = await h.sut.removePush(ref: "r1")
    #expect(fetched == nil, "Stale push must not leak into the pushes dict")
  }

  @Test
  @MainActor
  func didReceiveCloseClearsStoredPushes() async throws {
    let h = makeHarness()
    let confirmer = confirmSubscribeOnJoin(h)
    try await h.sut.subscribe()
    _ = await confirmer.value

    let joinRef = await h.sut.joinRef
    let message = RealtimeMessageV2(
      joinRef: joinRef, ref: "r1", topic: "t", event: "e", payload: [:]
    )
    let push = PushV2(channel: nil, message: message)
    _ = await h.sut.storePushIfJoinRefMatches(push, ref: "r1", joinRef: joinRef)

    await h.sut.didReceiveClose()

    let fetched = await h.sut.removePush(ref: "r1")
    #expect(fetched == nil, "Pushes should be cleared after didReceiveClose")
  }
}
