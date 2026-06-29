//
//  DisconnectTests.swift
//  RealtimeV3Tests
//
//  Created by Guilherme Souza on 29/06/26.
//

import Clocks
import ConcurrencyExtras
import Foundation
import Testing

@testable import RealtimeV3

@Suite struct DisconnectTests {

  // MARK: - Helpers

  /// Advance the TestClock in small steps with yields, up to `maxAttempts`, without waiting
  /// for a specific condition. Used to prove "nothing happened" after disconnect.
  private func advanceClockBeyondBackoff(
    clock: TestClock<Duration>,
    step: Duration = .seconds(1),
    steps: Int = 40
  ) async {
    for _ in 0..<steps {
      await Task.yield()
      await clock.advance(by: step)
      for _ in 0..<10 {
        await Task.yield()
      }
    }
  }

  // MARK: - Tests

  @Test func disconnectClosesAndDoesNotReconnect() async throws {
    let (transport, _) = InMemoryTransport.pair()
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
    #expect(await transport.connectCallCount == 1)

    // Collect status values into an array for later assertion.
    let statusStream = await rt.status
    let observedStates = LockIsolated<[ConnectionStatus.State]>([])
    let observerTask = Task {
      for await s in statusStream {
        observedStates.withValue { $0.append(s.state) }
      }
    }
    defer { observerTask.cancel() }

    // Disconnect.
    await rt.disconnect()

    // Status must be .closed(.clientDisconnected).
    let statusAfterDisconnect = await rt.status.first(where: { _ in true })
    if let s = statusAfterDisconnect {
      if case .closed(let reason) = s.state {
        #expect(reason == .clientDisconnected)
      } else {
        Issue.record("Expected .closed(.clientDisconnected), got \(s.state)")
      }
    }

    // Advance the clock well past the backoff window (40 * 1s = 40s > max backoff of 30s).
    await advanceClockBeyondBackoff(clock: clock)

    // Transport must NOT have reconnected — connectCallCount stays at 1.
    #expect(
      await transport.connectCallCount == 1, "Transport should not reconnect after disconnect()")

    // Status should still be .closed(.clientDisconnected), not .reconnecting/.connected.
    let finalStatusStream = await rt.status
    if let finalStatus = await finalStatusStream.first(where: { _ in true }) {
      if case .closed(let reason) = finalStatus.state {
        #expect(reason == .clientDisconnected, "Status should stay .closed(.clientDisconnected)")
      } else {
        Issue.record("Expected .closed(.clientDisconnected), got \(finalStatus.state)")
      }
    }
  }

  @Test func connectAfterDisconnectReopens() async throws {
    let (transport, _) = InMemoryTransport.pair()
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

    // First connect.
    try await rt.connect()
    #expect(await transport.connectCallCount == 1)

    // Disconnect.
    await rt.disconnect()

    // Verify disconnected state.
    let postDisconnectStream = await rt.status
    if let s = await postDisconnectStream.first(where: { _ in true }) {
      if case .closed(let reason) = s.state {
        #expect(reason == .clientDisconnected)
      } else {
        Issue.record("Expected .closed(.clientDisconnected) after disconnect, got \(s.state)")
      }
    }

    // Second connect after disconnect should re-open.
    try await rt.connect()
    #expect(await transport.connectCallCount == 2, "Expected second transport.connect() call")

    // Status should be .connected.
    let reconnectedStream = await rt.status
    if let s = await reconnectedStream.first(where: { _ in true }) {
      if case .connected = s.state {
        // Good.
      } else {
        Issue.record("Expected .connected after second connect(), got \(s.state)")
      }
    }
  }

  @Test func channelCachePreservedAcrossDisconnect() async throws {
    let (transport, _) = InMemoryTransport.pair()
    let rt = Realtime(
      url: URL(string: "wss://x")!,
      apiKey: "k",
      transport: transport
    )

    try await rt.connect()

    // Obtain a channel reference.
    let c1 = await rt.channel("room:1")

    // Disconnect (should NOT evict the channel cache).
    await rt.disconnect()

    // Obtain the same topic — must return the cached channel.
    let c2 = await rt.channel("room:1")

    #expect(c1 === c2, "Channel cache must be preserved across disconnect()")
  }
}
