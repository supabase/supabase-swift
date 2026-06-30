//
//  ReconnectionTests.swift
//  RealtimeV3Tests
//
//  Created by Guilherme Souza on 29/06/26.
//

import Clocks
import ConcurrencyExtras
import Foundation
import IssueReporting
import Testing

@testable import RealtimeV3

@Suite struct ReconnectionTests {

  // MARK: - Helpers

  /// Advance the TestClock in small steps, yielding to the cooperative thread pool between each
  /// advance, until `condition()` returns true or `maxAttempts` is reached.
  ///
  /// This avoids the "advance-before-sleep-registered" hang class: the reconnection loop
  /// must call `clock.sleep(for:)` before the advance takes effect. By yielding first and
  /// advancing in a bounded loop we guarantee the sleep is installed before the advance.
  ///
  /// After each advance, we yield several times to give async work triggered by the clock
  /// (actor hops, transport.connect, status transitions, observer task) time to complete
  /// before checking the condition.
  private func advanceUntil(
    clock: TestClock<Duration>,
    step: Duration,
    maxAttempts: Int = 200,
    condition: () async -> Bool
  ) async {
    for _ in 0..<maxAttempts {
      // Yield so the reconnection loop can reach its clock.sleep call.
      await Task.yield()
      await clock.advance(by: step)
      // Yield several more times to let tasks that woke from the clock advance
      // complete their work (actor hops, transport.connect, status transitions).
      for _ in 0..<10 {
        await Task.yield()
      }
      if await condition() {
        return
      }
    }
  }

  // MARK: - Tests

  @Test func reconnectsAfterUnexpectedClose() async throws {
    let (transport, server) = InMemoryTransport.pair()
    let clock = TestClock()
    var config = Configuration.default
    config.clock = clock
    config.heartbeat = .seconds(25)
    config.reconnection = .exponentialBackoff(initial: .seconds(1), max: .seconds(30), jitter: 0)
    let rt = Realtime(
      url: URL(string: "wss://x")!,
      apiKey: "k",
      configuration: config,
      transport: transport
    )
    try await rt.connect()

    // Subscribe before triggering the close so we see all transitions.
    let statusStream = await rt.status

    // Observe status in a background task using advance-until pattern for determinism.
    let sawReconnecting = LockIsolated(false)
    let sawReconnected = LockIsolated(false)

    let observerTask = Task {
      for await s in statusStream {
        switch s.state {
        case .reconnecting:
          sawReconnecting.setValue(true)
        case .connected where sawReconnecting.value:
          sawReconnected.setValue(true)
          return
        default:
          break
        }
      }
    }
    defer { observerTask.cancel() }

    // Trigger server-initiated close.
    server.closeFromServer(code: 1006, reason: "abnormal")

    // Advance clock in bounded loop until we see .reconnecting then .connected.
    // The initial reconnect delay is 1 second (attempt=1, exponential backoff).
    await advanceUntil(clock: clock, step: .seconds(1)) {
      sawReconnected.value
    }

    #expect(sawReconnecting.value, "Expected to observe .reconnecting state")
    #expect(sawReconnected.value, "Expected to reconnect and observe .connected state")
    #expect(await transport.connectCallCount == 2, "Expected transport.connect to be called twice")
  }

  @Test func givesUpWhenPolicyReturnsNil() async throws {
    let (transport, server) = InMemoryTransport.pair()
    let clock = TestClock()
    var config = Configuration.default
    config.clock = clock
    config.heartbeat = .seconds(25)
    config.reconnection = .never  // always returns nil → give up immediately
    let rt = Realtime(
      url: URL(string: "wss://x")!,
      apiKey: "k",
      configuration: config,
      transport: transport
    )
    try await rt.connect()

    let statusStream = await rt.status

    let sawClosed = LockIsolated(false)
    let observerTask = Task {
      for await s in statusStream {
        if case .closed(.transportFailure) = s.state {
          sawClosed.setValue(true)
          return
        }
      }
    }
    defer { observerTask.cancel() }

    // Trigger server-initiated close.
    server.closeFromServer(code: 1006, reason: "abnormal")

    // Yield repeatedly until we see .closed(.transportFailure) (no clock advance needed
    // since policy returns nil immediately — no sleep happens).
    for _ in 0..<200 {
      await Task.yield()
      if sawClosed.value { break }
    }

    #expect(
      sawClosed.value, "Expected .closed(.transportFailure) when reconnection policy is .never")
    // Transport should only have been called once (no reconnect attempt).
    #expect(await transport.connectCallCount == 1)
  }
}
