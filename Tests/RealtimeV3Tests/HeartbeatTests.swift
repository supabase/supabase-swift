//
//  HeartbeatTests.swift
//  RealtimeV3Tests
//
//  Created by Guilherme Souza on 29/06/26.
//

import Clocks
import ConcurrencyExtras
import Foundation
import Helpers
import IssueReporting
import Testing

@testable import RealtimeV3

@Suite struct HeartbeatTests {

  // MARK: - Helpers

  /// Advances `clock` in small steps, yielding to the cooperative thread pool between each
  /// advance, until `condition()` returns `true` or `maxAttempts` is reached.
  ///
  /// This avoids the "advance-before-sleep-registered" hang class: the heartbeat loop must
  /// call `clock.sleep(for:)` before the advance takes effect. By yielding first and
  /// advancing in a bounded loop we guarantee the sleep is installed before the advance.
  private func advanceUntil(
    clock: TestClock<Duration>,
    step: Duration,
    maxAttempts: Int = 50,
    condition: () async -> Bool
  ) async {
    for _ in 0..<maxAttempts {
      // Yield so the heartbeat loop can reach its clock.sleep call.
      await Task.yield()
      await clock.advance(by: step)
      if await condition() {
        return
      }
    }
  }

  // MARK: - Tests

  @Test func sendsHeartbeatAfterInterval() async throws {
    let (transport, server) = InMemoryTransport.pair()
    let clock = TestClock()
    var config = Configuration.default
    config.clock = clock
    config.heartbeat = .seconds(25)
    let rt = Realtime(
      url: URL(string: "wss://x")!,
      apiKey: "k",
      configuration: config,
      transport: transport
    )
    try await rt.connect()

    // Collect frames that arrive on the clientSentFrames stream.
    // Start this task BEFORE advancing the clock so we don't miss the frame.
    let collectedFrames = LockIsolated([TransportFrame]())
    let collectorTask = Task {
      var it = server.clientSentFrames.makeAsyncIterator()
      while let frame = await it.next() {
        collectedFrames.withValue { $0.append(frame) }
      }
    }
    defer { collectorTask.cancel() }

    // Advance the clock until a heartbeat frame is observed (or max attempts).
    await advanceUntil(clock: clock, step: .seconds(1)) {
      collectedFrames.withValue { frames in
        frames.contains { frame in
          if case .text(let t) = frame {
            return t.contains("heartbeat")
          }
          return false
        }
      }
    }

    // Assert a heartbeat text frame was sent.
    let heartbeatFrame = collectedFrames.withValue { frames in
      frames.first { frame in
        if case .text(let t) = frame { return t.contains("heartbeat") }
        return false
      }
    }

    if let heartbeatFrame, case .text(let t) = heartbeatFrame {
      #expect(t.contains("\"heartbeat\""))
      #expect(t.contains("\"phoenix\""))
    } else {
      Issue.record("Expected a heartbeat text frame to be sent after the interval elapsed")
    }
  }

  @Test func heartbeatContainsRefAndPhoenixTopic() async throws {
    let (transport, server) = InMemoryTransport.pair()
    let clock = TestClock()
    var config = Configuration.default
    config.clock = clock
    config.heartbeat = .seconds(25)
    let rt = Realtime(
      url: URL(string: "wss://x")!,
      apiKey: "k",
      configuration: config,
      transport: transport
    )
    try await rt.connect()

    let collectedFrames = LockIsolated([TransportFrame]())
    let collectorTask = Task {
      var it = server.clientSentFrames.makeAsyncIterator()
      while let frame = await it.next() {
        collectedFrames.withValue { $0.append(frame) }
      }
    }
    defer { collectorTask.cancel() }

    await advanceUntil(clock: clock, step: .seconds(1)) {
      collectedFrames.withValue { frames in
        frames.contains { frame in
          if case .text(let t) = frame { return t.contains("heartbeat") }
          return false
        }
      }
    }

    let frame = collectedFrames.withValue { frames in
      frames.first { frame in
        if case .text(let t) = frame { return t.contains("heartbeat") }
        return false
      }
    }

    if let frame, case .text(let t) = frame {
      #expect(t.contains("\"phoenix\""))
      // The ref field should be a non-null string (array position 1).
      // Quick structural check: the second element in [joinRef, ref, topic, event, payload]
      // should be a non-null ref string. Just verify JSON parses as array with 5 elements.
      let data = Data(t.utf8)
      if let arr = try? JSONDecoder().decode([AnyJSON].self, from: data) {
        #expect(arr.count == 5)
        // joinRef should be null, ref should be non-null string.
        #expect(arr[0] == .null)
        #expect(arr[1].stringValue != nil)
        #expect(arr[2].stringValue == "phoenix")
        #expect(arr[3].stringValue == "heartbeat")
      } else {
        Issue.record("Failed to decode heartbeat frame as JSON array")
      }
    } else {
      Issue.record("No heartbeat frame found")
    }
  }

  @Test func heartbeatLatencyIsPopulatedAfterRoundTrip() async throws {
    let (transport, server) = InMemoryTransport.pair()
    let clock = TestClock()
    var config = Configuration.default
    config.clock = clock
    config.heartbeat = .seconds(25)
    let rt = Realtime(
      url: URL(string: "wss://x")!,
      apiKey: "k",
      configuration: config,
      transport: transport
    )
    try await rt.connect()

    // Collect frames the client sends so we can extract the heartbeat ref.
    let collectedFrames = LockIsolated([TransportFrame]())
    let collectorTask = Task {
      var it = server.clientSentFrames.makeAsyncIterator()
      while let frame = await it.next() {
        collectedFrames.withValue { $0.append(frame) }
      }
    }
    defer { collectorTask.cancel() }

    // Advance until a heartbeat frame is observed on the wire.
    await advanceUntil(clock: clock, step: .seconds(1), maxAttempts: 300) {
      collectedFrames.withValue { frames in
        frames.contains { frame in
          if case .text(let t) = frame { return t.contains("heartbeat") }
          return false
        }
      }
    }

    // Extract the ref from the heartbeat frame (array position [1]).
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
      Issue.record("Could not extract heartbeat ref from sent frame")
      return
    }

    // Wait until the registry has registered the pending push for this ref,
    // so we know awaitReply is suspended and will receive our injected reply.
    for _ in 0..<300 {
      await Task.yield()
      if await rt._test_pendingCount > 0 { break }
    }

    // Subscribe to the status stream before injecting the reply.
    let statusStream = await rt.status

    // Inject the server's phx_reply for this heartbeat ref.
    let replyJSON =
      "[null,\"\(ref)\",\"phoenix\",\"phx_reply\",{\"status\":\"ok\",\"response\":{}}]"
    server.send(.text(replyJSON))

    // Observe the status stream until a ConnectionStatus with non-nil latency appears.
    let sawLatency = LockIsolated(false)
    let statusTask = Task {
      for await s in statusStream {
        if s.latency != nil {
          sawLatency.setValue(true)
          return
        }
      }
    }

    // Give the cooperative scheduler enough time to route the frame and update latency.
    for _ in 0..<300 {
      await Task.yield()
      if sawLatency.value { break }
    }
    statusTask.cancel()

    if !sawLatency.value {
      Issue.record("Expected ConnectionStatus.latency to be non-nil after heartbeat round-trip")
    }
  }

  @Test func heartbeatTimeoutTriggersConnectionLost() async throws {
    let (transport, server) = InMemoryTransport.pair()
    let clock = TestClock()
    var config = Configuration.default
    config.clock = clock
    config.heartbeat = .seconds(25)
    let rt = Realtime(
      url: URL(string: "wss://x")!,
      apiKey: "k",
      configuration: config,
      transport: transport
    )
    try await rt.connect()

    // Subscribe to status changes.
    let statusStream = await rt.status

    // Discard connection frames so the server buffer doesn't fill.
    let drainTask = Task {
      var it = server.clientSentFrames.makeAsyncIterator()
      while await it.next() != nil {}
    }
    defer { drainTask.cancel() }

    // Advance past the heartbeat interval (sends the heartbeat frame).
    await advanceUntil(clock: clock, step: .seconds(1)) {
      await rt._test_pendingCount > 0
    }

    // Now advance past the heartbeat timeout WITHOUT sending a reply — the registry
    // timeout task also sleeps on `configuration.heartbeat`. Advance until
    // connection transitions away from .connected.
    // Note: with Task 13 reconnection, the state transitions to .reconnecting (not .idle/.closed)
    // unless the policy gives up immediately. The default policy retries, so we accept
    // .reconnecting, .idle, or .closed as evidence that the heartbeat timeout was detected.
    let sawDisconnected = LockIsolated(false)
    let statusCheckTask = Task {
      for await s in statusStream {
        switch s.state {
        case .idle, .closed, .reconnecting:
          sawDisconnected.setValue(true)
          return
        default:
          break
        }
      }
    }

    await advanceUntil(clock: clock, step: .seconds(1), maxAttempts: 300) {
      sawDisconnected.value
    }
    statusCheckTask.cancel()

    #expect(
      sawDisconnected.value,
      "Expected connection to transition away from .connected after heartbeat timeout")
  }
}
