import ConcurrencyExtras
import Foundation
import Logging
import TestHelpers
import Testing

@testable import Realtime

@Suite
struct ChannelStateManagerTests {
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
    timeout: Duration = .milliseconds(200),
    maxRetryAttempts: Int = 3,
    retryDelay: @escaping @Sendable (Int) -> Duration = { _ in .milliseconds(10) }
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
      logger: supabaseDefaultLogger(label: "io.supabase.realtime"),
      maxRetryAttempts: maxRetryAttempts,
      timeout: timeout,
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

  private func confirmSubscribeOnJoin(_ h: Harness) -> Task<Void, Never> {
    Task { [h] in
      while h.joinCallCount.value == 0 {
        try? await Task.sleep(nanoseconds: 5_000_000)
      }
      await h.sut.didReceiveSubscribedOK()
    }
  }

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

  @Test
  func subscribePushesJoinAndTransitionsOnConfirmation() async throws {
    let h = makeHarness()

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

    try? await Task.sleep(nanoseconds: 20_000_000)
    await h.sut.didReceiveSubscribedOK()

    try await first
    try await second

    #expect(h.joinCallCount.value == 1, "Only one phx_join should be pushed")
  }

  @Test
  func subscribeRetriesOnTimeoutThenSucceeds() async throws {
    let h = makeHarness(timeout: .milliseconds(50), maxRetryAttempts: 3)

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
    let h = makeHarness(timeout: .milliseconds(50), maxRetryAttempts: 2)

    do {
      try await h.sut.subscribe()
      Issue.record("Expected subscribe to throw after max retries")
    } catch {
      #expect((error as? RealtimeError)?.kind == .maxRetryAttemptsReached)
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
    let h = makeHarness(timeout: .milliseconds(200), maxRetryAttempts: 1)
    h.ensureConnected.setValue(false)

    do {
      try await h.sut.subscribe()
      Issue.record("Expected subscribe to throw when socket is not connected")
    } catch {
    }

    let state = await h.sut.state
    guard case .unsubscribed = state else {
      Issue.record("Expected .unsubscribed, got \(state)")
      return
    }
  }

  @Test
  func subscribeRetriesWhenSocketConnectFailsTransiently() async throws {
    let h = makeHarness(
      timeout: .seconds(1), maxRetryAttempts: 3, retryDelay: { _ in .milliseconds(50) })
    h.ensureConnected.setValue(false)

    let recovery = Task { [h] in
      try? await Task.sleep(nanoseconds: 20_000_000)
      h.ensureConnected.setValue(true)
    }
    let confirmer = confirmSubscribeOnJoin(h)

    try await h.sut.subscribe()
    _ = await recovery.value
    _ = await confirmer.value

    let state = await h.sut.state
    guard case .subscribed = state else {
      Issue.record("Expected .subscribed after transient connect failure, got \(state)")
      return
    }
  }

  @Test
  func connectFailureDoesNotSurfaceAsCancellationError() async {
    let h = makeHarness(
      timeout: .milliseconds(200), maxRetryAttempts: 2, retryDelay: { _ in .milliseconds(10) })
    h.ensureConnected.setValue(false)

    do {
      try await h.sut.subscribe()
      Issue.record("Expected subscribe to throw when socket is not connected")
    } catch {
      #expect(!(error is CancellationError), "Connect failure surfaced as CancellationError")
      #expect((error as? RealtimeError)?.kind == .maxRetryAttemptsReached)
    }
  }

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
    let h = makeHarness(timeout: .seconds(5), maxRetryAttempts: 1)

    let subscribeTask = Task { try? await h.sut.subscribe() }

    while h.joinCallCount.value == 0 {
      try? await Task.sleep(nanoseconds: 5_000_000)
    }

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

  @Test
  func serverCloseDuringSubscribeSurfacesTypedError() async {
    let h = makeHarness(timeout: .seconds(5), maxRetryAttempts: 1)

    let subscribeTask = Task { try await h.sut.subscribe() }

    while h.joinCallCount.value == 0 {
      try? await Task.sleep(nanoseconds: 5_000_000)
    }
    await h.sut.didReceiveClose()

    do {
      try await subscribeTask.value
      Issue.record("Expected subscribe to throw after server close")
    } catch {
      #expect(!(error is CancellationError), "Server close surfaced as CancellationError")
      #expect(
        (error as? RealtimeError)?.kind == .channelClosedByServer,
        "Expected channelClosedByServer, got \(error)"
      )
    }
  }

  @Test
  func didReceiveCloseIgnoresStaleJoinRef() async throws {
    let h = makeHarness()

    let confirmer = confirmSubscribeOnJoin(h)
    try await h.sut.subscribe()
    _ = await confirmer.value

    let applied = await h.sut.didReceiveClose(joinRef: "stale-join-ref")
    #expect(!applied, "Close for a stale join_ref must be ignored")

    let state = await h.sut.state
    guard case .subscribed = state else {
      Issue.record("Stale close changed state to \(state)")
      return
    }

    let currentJoinRef = await h.sut.joinRef
    let appliedCurrent = await h.sut.didReceiveClose(joinRef: currentJoinRef)
    #expect(appliedCurrent, "Close for the current join_ref must be applied")

    let finalState = await h.sut.state
    guard case .unsubscribed = finalState else {
      Issue.record("Expected .unsubscribed after matching close, got \(finalState)")
      return
    }
  }

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
    let stateChanges = await h.sut.stateChanges
    let observer = Task { [stateChanges] in
      for await state in stateChanges {
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

  @Test
  func clientChangesAreForwardedToJoinOperation() async throws {
    let h = makeHarness()
    let config = PostgresJoinConfig(event: .insert, schema: "public", table: "users", filter: nil)
    h.clientChanges.withValue { $0.append(config) }

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

    let staleJoinRef = await h.sut.joinRef

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
