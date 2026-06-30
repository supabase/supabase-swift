//
//  LoggingTests.swift
//  RealtimeV3Tests
//
//  Created by Guilherme Souza on 29/06/26.
//

import Clocks
import ConcurrencyExtras
import Foundation
import Helpers
import Testing

@testable import RealtimeV3

// MARK: - SpyLogger

/// A test double that captures every LogEvent emitted by the SDK.
final class SpyLogger: RealtimeLogger {
  let events = LockIsolated<[LogEvent]>([])

  func log(_ event: LogEvent) {
    events.withValue { $0.append(event) }
  }
}

// MARK: - LoggingTests

@Suite struct LoggingTests {

  // MARK: - connectEmitsConnectionLog

  /// Verifies that calling connect() emits at least one LogEvent with category == .connection.
  @Test func connectEmitsConnectionLog() async throws {
    let spy = SpyLogger()
    let (transport, _) = InMemoryTransport.pair()
    var config = Configuration.default
    config.logger = spy

    let rt = Realtime(
      url: URL(string: "wss://x")!,
      apiKey: "k",
      configuration: config,
      transport: transport
    )
    try await rt.connect()

    // Yield a few times to allow any deferred log emissions to propagate.
    for _ in 0..<10 { await Task.yield() }

    let captured = spy.events.value
    let hasConnection = captured.contains { $0.category == .connection }
    #expect(hasConnection, "Expected at least one .connection-category LogEvent after connect()")
  }

  // MARK: - heartbeatEmitsRttMetric

  /// Verifies that after a heartbeat round-trip, a LogEvent with metadata["heartbeat.rtt_ms"] is emitted.
  @Test func heartbeatEmitsRttMetric() async throws {
    let spy = SpyLogger()
    let (transport, server) = InMemoryTransport.pair()
    let clock = TestClock()
    var config = Configuration.default
    config.clock = clock
    config.heartbeat = .seconds(25)
    config.logger = spy

    let rt = Realtime(
      url: URL(string: "wss://x")!,
      apiKey: "k",
      configuration: config,
      transport: transport
    )
    try await rt.connect()

    // Collect client-sent frames so we can find the heartbeat ref.
    let collectedFrames = LockIsolated([TransportFrame]())
    let collectorTask = Task {
      var it = server.clientSentFrames.makeAsyncIterator()
      while let frame = await it.next() {
        collectedFrames.withValue { $0.append(frame) }
      }
    }
    defer { collectorTask.cancel() }

    // Advance clock until a heartbeat frame is on the wire.
    for _ in 0..<300 {
      await Task.yield()
      await clock.advance(by: .seconds(1))
      let found = collectedFrames.withValue { frames in
        frames.contains {
          if case .text(let t) = $0 { return t.contains("heartbeat") }
          return false
        }
      }
      if found { break }
    }

    // Extract the heartbeat ref.
    let heartbeatRef: String? = collectedFrames.withValue { frames in
      guard
        let frame = frames.first(where: {
          if case .text(let t) = $0 { return t.contains("heartbeat") }
          return false
        }),
        case .text(let t) = frame,
        let data = t.data(using: .utf8),
        let arr = try? JSONDecoder().decode([AnyJSON].self, from: data),
        arr.count >= 2,
        let ref = arr[1].stringValue
      else { return nil }
      return ref
    }

    guard let ref = heartbeatRef else {
      Issue.record("Could not extract heartbeat ref")
      return
    }

    // Wait until the registry has the pending push registered.
    for _ in 0..<300 {
      await Task.yield()
      if await rt._test_pendingCount > 0 { break }
    }

    // Inject the server reply so the heartbeat round-trip completes.
    let replyJSON =
      "[null,\"\(ref)\",\"phoenix\",\"phx_reply\",{\"status\":\"ok\",\"response\":{}}]"
    server.send(.text(replyJSON))

    // Yield until the RTT log event appears (bounded).
    var sawRttMetric = false
    for _ in 0..<300 {
      await Task.yield()
      let captured = spy.events.value
      if captured.contains(where: { $0.metadata["heartbeat.rtt_ms"] != nil }) {
        sawRttMetric = true
        break
      }
    }

    #expect(
      sawRttMetric,
      "Expected a LogEvent with metadata[\"heartbeat.rtt_ms\"] after heartbeat round-trip")
  }

  // MARK: - reconnectAttemptEmitsMetric

  /// Verifies that a forced reconnect emits a LogEvent with metadata["reconnect.attempt"].
  @Test func reconnectAttemptEmitsMetric() async throws {
    let spy = SpyLogger()
    let (transport, server) = InMemoryTransport.pair()
    let clock = TestClock()
    var config = Configuration.default
    config.clock = clock
    config.heartbeat = .seconds(25)
    config.reconnection = .exponentialBackoff(initial: .seconds(1), max: .seconds(30), jitter: 0)
    config.logger = spy

    let rt = Realtime(
      url: URL(string: "wss://x")!,
      apiKey: "k",
      configuration: config,
      transport: transport
    )
    try await rt.connect()

    // Trigger a server-initiated close to start the reconnection loop.
    server.closeFromServer(code: 1001, reason: "server went away")

    // Wait for the reconnection loop to start.
    for _ in 0..<300 {
      await Task.yield()
      if await rt.isReconnecting { break }
    }

    // Advance the clock to trigger the first reconnect attempt's delay.
    for _ in 0..<300 {
      await Task.yield()
      await clock.advance(by: .seconds(1))
      for _ in 0..<10 { await Task.yield() }
      let found = spy.events.value.contains { $0.metadata["reconnect.attempt"] != nil }
      if found { break }
    }

    let sawReconnectMetric = spy.events.value.contains { $0.metadata["reconnect.attempt"] != nil }
    #expect(
      sawReconnectMetric,
      "Expected a LogEvent with metadata[\"reconnect.attempt\"] during reconnection")
  }
}
