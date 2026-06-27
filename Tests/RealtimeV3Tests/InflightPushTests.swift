//
//  InflightPushTests.swift
//  RealtimeV3
//
//  Created by Guilherme Souza on 27/06/26.
//

import Clocks
import Foundation
import Testing

@testable import RealtimeV3

@Suite struct InflightPushTests {
  @Test func resolvesPendingReply() async throws {
    let registry = InflightPushRegistry()
    let clock = TestClock()
    let replyTask = Task {
      try await registry.awaitReply(
        ref: "1", timeout: .seconds(10), clock: clock, timeoutError: .channelJoinTimeout
      )
    }
    // Wait until the push is registered before resolving — otherwise `resolve`
    // can run first, find nothing, and the later-registered continuation would
    // never be resumed (it would hang until the timeout, which never advances).
    while await registry.pendingCount == 0 {
      await Task.yield()
    }
    await registry.resolve(ref: "1", status: "ok", response: [:])
    let result = try await replyTask.value
    #expect(result.status == "ok")
  }

  @Test func timesOutWhenNoReply() async throws {
    let registry = InflightPushRegistry()
    let clock = TestClock()

    // Start the await in a detached task so we can advance the clock independently.
    let replyTask = Task {
      try await registry.awaitReply(
        ref: "2", timeout: .seconds(5), clock: clock, timeoutError: .broadcastAckTimeout
      )
    }

    // Deterministically wait until the push is registered before driving the
    // clock. `awaitReply` spawns an internal timeout task that sleeps on the
    // clock; advancing before that sleep is registered would be a no-op and
    // hang the test, so we advance-until-fired: keep yielding/advancing (an
    // idempotent operation on a `TestClock`) until the pending entry clears,
    // which means the timeout fired and resumed the continuation.
    while await registry.pendingCount == 0 {
      await Task.yield()
    }
    var attempts = 0
    while await registry.pendingCount > 0, attempts < 1000 {
      await clock.advance(by: .seconds(5))
      await Task.yield()
      attempts += 1
    }

    do {
      _ = try await replyTask.value
      Issue.record("Expected broadcastAckTimeout but the push succeeded")
    } catch let error as RealtimeError {
      #expect(error == .broadcastAckTimeout)
    } catch {
      Issue.record("Unexpected non-RealtimeError: \(error)")
    }
  }
}
