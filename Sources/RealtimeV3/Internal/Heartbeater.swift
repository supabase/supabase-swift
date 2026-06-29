//
//  Heartbeater.swift
//  RealtimeV3
//
//  Created by Guilherme Souza on 29/06/26.
//

import Clocks
import Foundation

/// Manages the periodic heartbeat for an active WebSocket connection.
///
/// The heartbeat loop:
/// 1. Sleeps `configuration.heartbeat` on `configuration.clock`.
/// 2. Sends a `[null, ref, "phoenix", "heartbeat", {}]` text frame.
/// 3. Awaits a `phx_reply` via `InflightPushRegistry.awaitReply`.
/// 4. On success, measures round-trip time and updates `ConnectionStatus.latency`.
/// 5. On timeout (throws), calls `onConnectionLost` so the actor can react.
///
/// Start one instance after a successful `connect()` and cancel its `task` on disconnect.
struct Heartbeater: Sendable {
  typealias SendFrame = @Sendable (String) async throws -> Void
  typealias AwaitReply = @Sendable (_ ref: String) async throws -> PushReply
  typealias UpdateLatency = @Sendable (Duration) async -> Void
  typealias OnConnectionLost = @Sendable (RealtimeError) async -> Void

  private let heartbeat: Duration
  private let clock: any Clock<Duration> & Sendable
  /// Wall-clock used solely for round-trip latency measurement (not for scheduling).
  private let wallClock = ContinuousClock()
  private let refGenerator: RefGenerator
  private let sendFrame: SendFrame
  private let awaitReply: AwaitReply
  private let updateLatency: UpdateLatency
  private let onConnectionLost: OnConnectionLost

  init(
    heartbeat: Duration,
    clock: any Clock<Duration> & Sendable,
    refGenerator: RefGenerator,
    sendFrame: @escaping SendFrame,
    awaitReply: @escaping AwaitReply,
    updateLatency: @escaping UpdateLatency,
    onConnectionLost: @escaping OnConnectionLost
  ) {
    self.heartbeat = heartbeat
    self.clock = clock
    self.refGenerator = refGenerator
    self.sendFrame = sendFrame
    self.awaitReply = awaitReply
    self.updateLatency = updateLatency
    self.onConnectionLost = onConnectionLost
  }

  /// Starts the heartbeat loop as an unstructured `Task`. Returns the task handle
  /// so the caller can cancel it on disconnect or connection loss.
  func start() -> Task<Void, Never> {
    Task {
      await run()
    }
  }

  private func run() async {
    while !Task.isCancelled {
      // Sleep for the heartbeat interval before the first send, matching V2 behaviour.
      do {
        try await clock.sleep(for: heartbeat)
      } catch {
        // CancellationError: task was cancelled — clean exit.
        return
      }
      guard !Task.isCancelled else { return }

      await sendHeartbeat()
    }
  }

  private func sendHeartbeat() async {
    let ref = refGenerator.next()
    // Use ContinuousClock for wall-time latency measurement; scheduling uses `clock`.
    let sentAt = wallClock.now

    // Encode the heartbeat frame: [null, ref, "phoenix", "heartbeat", {}]
    let serializer = PhoenixSerializer()
    let frame: String
    do {
      frame = try serializer.encodeText(
        joinRef: nil,
        ref: ref,
        topic: "phoenix",
        event: PhoenixEvent.heartbeat.rawValue,
        payload: [:]
      )
    } catch {
      // Encoding failed — treat as connection lost.
      await onConnectionLost(.transportFailure(underlying: error))
      return
    }

    // Send the heartbeat frame.
    do {
      try await sendFrame(frame)
    } catch {
      await onConnectionLost(.transportFailure(underlying: error))
      return
    }

    // Await the reply. Timeout equals the heartbeat interval (same as V2).
    do {
      _ = try await awaitReply(ref)
      let roundTrip = sentAt.duration(to: wallClock.now)
      await updateLatency(roundTrip)
    } catch let error as RealtimeError {
      await onConnectionLost(error)
    } catch {
      await onConnectionLost(.cancelled)
    }
  }
}
