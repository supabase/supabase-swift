//
//  WaitUntil.swift
//  TestHelpers
//
//  Created by Guilherme Souza on 16/09/26.
//

public import Foundation

/// Polls `condition` until it returns `true` or `timeout` elapses.
///
/// Swift Testing has no direct equivalent of `XCTestExpectation` +
/// `fulfillment(of:timeout:)` for "wait for an async condition driven by a
/// concurrently-running task". Tests that used to fulfill an expectation from
/// a background task flip a `LockIsolated` flag/counter instead, and await
/// this helper to observe it.
@discardableResult
public func waitUntil(
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
