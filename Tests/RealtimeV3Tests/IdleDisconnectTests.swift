//
//  IdleDisconnectTests.swift
//  RealtimeV3Tests
//
//  Created by Guilherme Souza on 29/06/26.
//

import Clocks
import ConcurrencyExtras
import Foundation
import Testing

@testable import RealtimeV3

@Suite struct IdleDisconnectTests {

  // MARK: - Helpers

  /// Advance the TestClock in small steps with yields until `condition()` returns true
  /// or `maxAttempts` is reached. Uses the same bounded advance-until pattern as
  /// ReconnectionTests to avoid hangs.
  private func advanceUntil(
    clock: TestClock<Duration>,
    step: Duration,
    maxAttempts: Int = 300,
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

  // MARK: - closesSocketAfterIdleTimeout

  /// When the last live channel leaves, the socket should close after
  /// `disconnectOnEmptyChannelsAfter` elapses with no new channels joining.
  @Test func closesSocketAfterIdleTimeout() async throws {
    let (transport, server) = InMemoryTransport.pair()
    let clock = TestClock()
    var config = Configuration.default
    config.clock = clock
    // Use a heartbeat longer than the entire test so the heartbeat does not interfere.
    config.heartbeat = .seconds(500)
    config.disconnectOnEmptyChannelsAfter = .seconds(50)
    // Disable auto-reconnect so a server-side close does not interfere.
    config.reconnection = .never
    let rt = Realtime(
      url: URL(string: "wss://x")!,
      apiKey: "k",
      configuration: config,
      transport: transport
    )

    server.autoReplyToJoins()
    server.autoReplyToLeaves()

    // Subscribe the channel so the socket opens and the channel reaches .joined.
    let channel = await rt.channel("room:1")
    try await channel.subscribe()

    // Confirm the channel is joined.
    let joinedState = await channel.state.first(where: { _ in true })
    #expect(joinedState == .joined)

    // Leave the channel — live count goes to 0 → idle timer should be armed.
    try await channel.leave()

    // Confirm channel is closed.
    let closedState = await channel.state.first(where: { _ in true })
    if case .closed(.userRequested) = closedState {
      // expected
    } else {
      Issue.record(
        "Expected .closed(.userRequested) after leave, got: \(String(describing: closedState))")
    }

    // The socket should NOT be closed yet (timer is running).
    let statusBeforeTimeout = await rt.status.first(where: { _ in true })
    if let s = statusBeforeTimeout {
      if case .connected = s.state {
        // Good — socket is still open.
      } else {
        Issue.record("Expected .connected before idle timeout, got: \(s.state)")
      }
    }

    // Advance the clock past the idle timeout: status should transition to .idle.
    let sawIdle = LockIsolated(false)
    let statusStream = await rt.status
    let observerTask = Task {
      for await s in statusStream {
        if case .idle = s.state {
          sawIdle.setValue(true)
          return
        }
      }
    }
    defer { observerTask.cancel() }

    await advanceUntil(clock: clock, step: .seconds(1)) {
      sawIdle.value
    }

    #expect(
      sawIdle.value, "Expected socket to transition to .idle after disconnectOnEmptyChannelsAfter")
    // Transport should only have been connected once (no reconnect triggered by idle close).
    #expect(await transport.connectCallCount == 1, "Idle close must not trigger reconnect")
  }

  // MARK: - joinBeforeTimeoutCancelsIdleClose

  /// When a new channel joins before the idle timer fires, the timer is cancelled
  /// and the socket stays open.
  @Test func joinBeforeTimeoutCancelsIdleClose() async throws {
    let (transport, server) = InMemoryTransport.pair()
    let clock = TestClock()
    var config = Configuration.default
    config.clock = clock
    // Use a heartbeat longer than the entire test so the heartbeat does not interfere.
    config.heartbeat = .seconds(500)
    config.disconnectOnEmptyChannelsAfter = .seconds(50)
    config.reconnection = .never
    let rt = Realtime(
      url: URL(string: "wss://x")!,
      apiKey: "k",
      configuration: config,
      transport: transport
    )

    server.autoReplyToJoins()
    server.autoReplyToLeaves()

    // Subscribe + leave to arm the idle timer.
    let ch1 = await rt.channel("room:1")
    try await ch1.subscribe()
    try await ch1.leave()

    // Advance by less than the timeout — timer should still be running.
    for _ in 0..<30 {
      await Task.yield()
      await clock.advance(by: .seconds(1))
      for _ in 0..<5 {
        await Task.yield()
      }
    }
    // Socket should still be open at 30s (timeout is 50s).
    let statusAt30s = await rt.status.first(where: { _ in true })
    if let s = statusAt30s {
      if case .connected = s.state {
        // Good.
      } else {
        Issue.record("Expected .connected at 30s (before idle timeout), got: \(s.state)")
      }
    }

    // Subscribe a second channel — this should cancel the idle timer.
    let ch2 = await rt.channel("room:2")
    try await ch2.subscribe()

    // Confirm ch2 joined.
    let ch2State = await ch2.state.first(where: { _ in true })
    #expect(ch2State == .joined)

    // Advance past the original 50s deadline — no idle close should happen.
    for _ in 0..<30 {
      await Task.yield()
      await clock.advance(by: .seconds(1))
      for _ in 0..<5 {
        await Task.yield()
      }
    }

    // Socket should still be connected (live channel ch2 is joined).
    let statusAfterOriginalDeadline = await rt.status.first(where: { _ in true })
    if let s = statusAfterOriginalDeadline {
      if case .connected = s.state {
        // Good — no idle close happened.
      } else {
        Issue.record("Expected .connected (idle close was cancelled), got: \(s.state)")
      }
    }

    // Transport should still have been connected only once — no idle reconnect.
    #expect(
      await transport.connectCallCount == 1,
      "No additional transport.connect() calls expected when idle timer was cancelled")
  }

  // MARK: - reconnectsAfterIdleClose

  /// After an idle close, a new subscribe() call should re-open the socket
  /// and successfully join the channel.
  @Test func reconnectsAfterIdleClose() async throws {
    let (transport, server) = InMemoryTransport.pair()
    let clock = TestClock()
    var config = Configuration.default
    config.clock = clock
    // Use a heartbeat longer than the entire test so the heartbeat does not interfere.
    config.heartbeat = .seconds(500)
    config.disconnectOnEmptyChannelsAfter = .seconds(50)
    config.reconnection = .never
    let rt = Realtime(
      url: URL(string: "wss://x")!,
      apiKey: "k",
      configuration: config,
      transport: transport
    )

    server.autoReplyToJoins()
    server.autoReplyToLeaves()

    // Subscribe + leave to arm the idle timer.
    let ch1 = await rt.channel("room:1")
    try await ch1.subscribe()
    try await ch1.leave()

    // Advance past the idle timeout to trigger idle close.
    let sawIdle = LockIsolated(false)
    let statusStream = await rt.status
    let observerTask = Task {
      for await s in statusStream {
        if case .idle = s.state {
          sawIdle.setValue(true)
          return
        }
      }
    }
    defer { observerTask.cancel() }

    await advanceUntil(clock: clock, step: .seconds(1)) {
      sawIdle.value
    }

    #expect(sawIdle.value, "Expected socket to close after idle timeout")
    #expect(await transport.connectCallCount == 1, "Only 1 connect before idle close")

    // Now subscribe a new channel — this should re-open the socket.
    let ch2 = await rt.channel("room:2")
    try await ch2.subscribe()

    // Transport should have been called a second time.
    #expect(
      await transport.connectCallCount == 2,
      "Expected a second transport.connect() after idle close + new subscribe()")

    // The new channel should be joined.
    let ch2State = await ch2.state.first(where: { _ in true })
    #expect(ch2State == .joined, "Expected ch2 to be .joined after reconnect")

    // Socket status should be .connected.
    let finalStatus = await rt.status.first(where: { _ in true })
    if let s = finalStatus {
      if case .connected = s.state {
        // Good.
      } else {
        Issue.record("Expected .connected after idle-close + reconnect, got: \(s.state)")
      }
    }
  }
}
