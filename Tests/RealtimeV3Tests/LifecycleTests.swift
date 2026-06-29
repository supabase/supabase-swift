//
//  LifecycleTests.swift
//  RealtimeV3Tests
//
//  Created by Guilherme Souza on 29/06/26.
//

import Clocks
import ConcurrencyExtras
import Foundation
import Testing

@testable import RealtimeV3

@Suite struct LifecycleTests {

  // MARK: - Helpers

  /// Advance the TestClock in small steps, yielding to the cooperative thread pool between each
  /// advance, until `condition()` returns true or `maxAttempts` is reached.
  private func advanceUntil(
    clock: TestClock<Duration>,
    step: Duration,
    maxAttempts: Int = 200,
    condition: () async -> Bool
  ) async {
    for _ in 0..<maxAttempts {
      await Task.yield()
      await clock.advance(by: step)
      for _ in 0..<10 {
        await Task.yield()
      }
      if await condition() {
        return
      }
    }
  }

  // MARK: - Tests

  /// When connected, then the socket drops while the app is backgrounded,
  /// a foreground event should trigger reconnect.
  @Test func foregroundAfterBackgroundDropReconnects() async throws {
    let (transport, server) = InMemoryTransport.pair()
    let clock = TestClock()
    var config = Configuration.default
    config.clock = clock
    config.heartbeat = .seconds(25)
    config.reconnection = .exponentialBackoff(initial: .seconds(1), max: .seconds(30), jitter: 0)
    config.lifecycle = .automatic

    let lifecycleSource = TestLifecycleEventSource()

    let rt = Realtime(
      url: URL(string: "wss://x")!,
      apiKey: "k",
      configuration: config,
      transport: transport,
      lifecycleSource: lifecycleSource
    )

    // Connect successfully.
    try await rt.connect()
    #expect(await transport.connectCallCount == 1)

    // Emit background event (app went to background).
    lifecycleSource.sendBackground()

    // Allow background notification to be processed.
    for _ in 0..<5 {
      await Task.yield()
    }

    // Simulate socket drop while in background (server closes the connection).
    server.closeFromServer(code: 1006, reason: "abnormal")

    // Allow the drop to be processed — the client should NOT auto-reconnect yet
    // (intentionalDisconnect is false, but we want lifecycle-driven reconnect on foreground).
    for _ in 0..<10 {
      await Task.yield()
    }

    // Emit foreground event — this should trigger reconnect.
    lifecycleSource.sendForeground()

    // Advance clock until we see a second connect attempt (reconnect).
    await advanceUntil(clock: clock, step: .seconds(1)) {
      await transport.connectCallCount >= 2
    }

    #expect(
      await transport.connectCallCount >= 2,
      "Expected transport.connect to be called again after foreground event following a drop"
    )
  }

  /// A foreground event while already connected should NOT trigger an extra connect.
  @Test func foregroundWhenConnectedIsNoOp() async throws {
    let (transport, _) = InMemoryTransport.pair()
    var config = Configuration.default
    config.heartbeat = .seconds(25)
    config.lifecycle = .automatic

    let lifecycleSource = TestLifecycleEventSource()

    let rt = Realtime(
      url: URL(string: "wss://x")!,
      apiKey: "k",
      configuration: config,
      transport: transport,
      lifecycleSource: lifecycleSource
    )

    // Connect successfully.
    try await rt.connect()
    #expect(await transport.connectCallCount == 1)

    // Emit foreground while already connected — should be a no-op.
    lifecycleSource.sendForeground()

    // Let any potential spurious connects happen.
    for _ in 0..<20 {
      await Task.yield()
    }

    // Connect count must stay at 1.
    #expect(
      await transport.connectCallCount == 1,
      "Foreground event when already connected should not trigger an extra connect"
    )
  }

  /// After an explicit disconnect(), a foreground event must NOT reconnect.
  @Test func manualDisconnectSuppressesLifecycleReconnect() async throws {
    let (transport, _) = InMemoryTransport.pair()
    let clock = TestClock()
    var config = Configuration.default
    config.clock = clock
    config.heartbeat = .seconds(25)
    config.reconnection = .exponentialBackoff(initial: .seconds(1), max: .seconds(30), jitter: 0)
    config.lifecycle = .automatic

    let lifecycleSource = TestLifecycleEventSource()

    let rt = Realtime(
      url: URL(string: "wss://x")!,
      apiKey: "k",
      configuration: config,
      transport: transport,
      lifecycleSource: lifecycleSource
    )

    // Connect successfully.
    try await rt.connect()
    #expect(await transport.connectCallCount == 1)

    // Intentional disconnect.
    await rt.disconnect()

    // Emit foreground — must NOT reconnect.
    lifecycleSource.sendForeground()

    // Advance clock well past backoff window to prove no reconnect occurs.
    for _ in 0..<40 {
      await Task.yield()
      await clock.advance(by: .seconds(1))
      for _ in 0..<5 {
        await Task.yield()
      }
    }

    #expect(
      await transport.connectCallCount == 1,
      "Foreground event after manual disconnect() must NOT reconnect"
    )
  }
}
