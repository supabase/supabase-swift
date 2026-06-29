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
    let sawClosed = LockIsolated(false)
    let statusCheckTask = Task {
      for await s in statusStream {
        switch s.state {
        case .idle, .closed:
          sawClosed.setValue(true)
          return
        default:
          break
        }
      }
    }

    await advanceUntil(clock: clock, step: .seconds(1), maxAttempts: 100) {
      sawClosed.value
    }
    statusCheckTask.cancel()

    #expect(
      sawClosed.value, "Expected connection to transition to idle/closed after heartbeat timeout")
  }
}
