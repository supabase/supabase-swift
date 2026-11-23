//
//  TestSupport.swift
//  RealtimeTests
//
//  Shared helpers used across the Swift Testing migration of RealtimeTests.
//

import ConcurrencyExtras
import Foundation

/// Polls `condition` until it returns `true` or `timeout` elapses.
///
/// Swift Testing has no direct equivalent of `XCTestExpectation` +
/// `fulfillment(of:timeout:)` for "wait for an async condition driven by a
/// concurrently-running task". Tests that used to fulfill an expectation from
/// a background task now flip a `LockIsolated` flag/counter instead, and await
/// this helper to observe it.
@discardableResult
func waitUntil(
  timeout: TimeInterval = 10.0,
  pollInterval: UInt64 = 10_000_000,
  condition: @escaping @Sendable () -> Bool
) async -> Bool {
  let deadline = Date().addingTimeInterval(timeout)
  while Date() < deadline {
    if condition() { return true }
    try? await Task.sleep(nanoseconds: pollInterval)
  }
  return condition()
}

/// Holds every caller of ``wait()`` until ``open()``. A cancelled caller keeps waiting, the way a
/// transport that has already opened its socket still returns it after its task is cancelled.
final class Gate: Sendable {
  private let state = LockIsolated<(isOpen: Bool, waiters: [CheckedContinuation<Void, Never>])>(
    (false, []))

  var waiterCount: Int { state.value.waiters.count }

  func wait() async {
    await withCheckedContinuation { continuation in
      let isOpen = state.withValue { state -> Bool in
        if !state.isOpen { state.waiters.append(continuation) }
        return state.isOpen
      }
      if isOpen { continuation.resume() }
    }
  }

  func open() {
    let waiters = state.withValue { state -> [CheckedContinuation<Void, Never>] in
      state.isOpen = true
      let waiters = state.waiters
      state.waiters = []
      return waiters
    }
    for waiter in waiters { waiter.resume() }
  }
}
