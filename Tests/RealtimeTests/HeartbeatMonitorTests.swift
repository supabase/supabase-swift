//
//  HeartbeatMonitorTests.swift
//  Realtime Tests
//
//  Created on 17/01/25.
//

import Foundation
import XCTest

@testable import Realtime

final class HeartbeatMonitorTests: XCTestCase {
  var monitor: HeartbeatMonitor!
  var sentHeartbeats: [String] = []
  var timeoutCount = 0
  var currentRef = 0

  override func setUp() async throws {
    try await super.setUp()
    sentHeartbeats = []
    timeoutCount = 0
    currentRef = 0
  }

  override func tearDown() async throws {
    if monitor != nil {
      await monitor.stop()
    }
    monitor = nil
    try await super.tearDown()
  }

  // MARK: - Helper

  func makeMonitor(interval: TimeInterval = 0.1) -> HeartbeatMonitor {
    HeartbeatMonitor(
      interval: interval,
      refGenerator: { [weak self] in
        guard let self else { return "0" }
        self.currentRef += 1
        return "\(self.currentRef)"
      },
      sendHeartbeat: { [weak self] ref in
        self?.sentHeartbeats.append(ref)
      },
      onTimeout: { [weak self] in
        self?.timeoutCount += 1
      },
      logger: nil
    )
  }

  // MARK: - Tests

  func testStartSendsHeartbeatsAtInterval() async throws {
    monitor = makeMonitor(interval: 0.05)

    await monitor.start()

    // Wait for a few heartbeats
    try await Task.sleep(nanoseconds: 250_000_000) // 0.25 seconds

    await monitor.stop()

    // Should have sent multiple heartbeats (at least 2 in 0.25s with 0.05s interval)
    // Note: Due to Task scheduling delays, we can't guarantee exact timing
    XCTAssertGreaterThanOrEqual(sentHeartbeats.count, 2, "Should send multiple heartbeats")
    // Verify refs increment correctly
    for (index, ref) in sentHeartbeats.enumerated() {
      XCTAssertEqual(ref, "\(index + 1)", "Refs should increment")
    }
  }

  func testStopCancelsHeartbeats() async throws {
    monitor = makeMonitor(interval: 0.05)

    await monitor.start()

    try await Task.sleep(nanoseconds: 60_000_000) // 0.06 seconds
    await monitor.stop()

    let count = sentHeartbeats.count

    // Wait longer
    try await Task.sleep(nanoseconds: 100_000_000)

    // Should not have sent more heartbeats after stop
    XCTAssertEqual(sentHeartbeats.count, count, "Should not send heartbeats after stop")
  }

  func testOnHeartbeatResponseClearsPendingRef() async throws {
    monitor = makeMonitor(interval: 0.1)

    await monitor.start()

    // Wait for first heartbeat
    try await Task.sleep(nanoseconds: 120_000_000)

    XCTAssertEqual(sentHeartbeats.count, 1)
    XCTAssertEqual(timeoutCount, 0)

    // Acknowledge the heartbeat
    await monitor.onHeartbeatResponse(ref: "1")

    // Wait for next heartbeat
    try await Task.sleep(nanoseconds: 120_000_000)

    await monitor.stop()

    // Should have sent second heartbeat without timeout
    XCTAssertEqual(sentHeartbeats.count, 2)
    XCTAssertEqual(timeoutCount, 0, "Should not timeout when acknowledged")
  }

  func testTimeoutWhenHeartbeatNotAcknowledged() async throws {
    monitor = makeMonitor(interval: 0.1)

    await monitor.start()

    // Wait for first heartbeat
    try await Task.sleep(nanoseconds: 120_000_000)

    XCTAssertEqual(sentHeartbeats.count, 1)

    // DON'T acknowledge - let it timeout

    // Wait for timeout check
    try await Task.sleep(nanoseconds: 120_000_000)

    await monitor.stop()

    // Should have detected timeout and NOT sent second heartbeat
    XCTAssertEqual(sentHeartbeats.count, 1, "Should not send new heartbeat on timeout")
    XCTAssertEqual(timeoutCount, 1, "Should have detected timeout")
  }

  func testMismatchedRefDoesNotClearPending() async throws {
    monitor = makeMonitor(interval: 0.1)

    await monitor.start()

    // Wait for first heartbeat
    try await Task.sleep(nanoseconds: 120_000_000)

    XCTAssertEqual(sentHeartbeats, ["1"])

    // Acknowledge with wrong ref
    await monitor.onHeartbeatResponse(ref: "999")

    // Wait for next interval
    try await Task.sleep(nanoseconds: 120_000_000)

    await monitor.stop()

    // Should timeout because correct ref was not acknowledged
    XCTAssertEqual(timeoutCount, 1, "Should timeout with mismatched ref")
  }

  func testRestartCreatesNewMonitor() async throws {
    monitor = makeMonitor(interval: 0.05)

    await monitor.start()
    try await Task.sleep(nanoseconds: 60_000_000)
    let firstCount = sentHeartbeats.count

    // Restart
    await monitor.start()

    // Old task should be cancelled, new one started
    try await Task.sleep(nanoseconds: 60_000_000)

    await monitor.stop()

    // Should have continued sending
    XCTAssertGreaterThan(sentHeartbeats.count, firstCount)
  }

  func testStopWhenNotStartedIsNoop() async {
    monitor = makeMonitor()

    // Should not crash
    await monitor.stop()
    await monitor.stop()
  }
}
