//
//  Realtime+Heartbeat.swift
//  RealtimeV3
//
//  Created by Guilherme Souza on 29/06/26.
//

import Clocks
import Foundation

// MARK: - Heartbeat

extension Realtime {
  /// Starts the heartbeat loop and stores the task handle so it can be cancelled.
  func startHeartbeat() {
    heartbeatTask?.cancel()
    let heartbeater = Heartbeater(
      heartbeat: configuration.heartbeat,
      clock: configuration.clock,
      beat: { [weak self] in try await self?._sendHeartbeat() },
      onConnectionLost: { [weak self] error in
        await self?.handleConnectionLost(error)
      }
    )
    heartbeatTask = heartbeater.start()
  }

  /// Sends one `[null, ref, "phoenix", "heartbeat", {}]` frame on the current connection and
  /// awaits its reply, updating `ConnectionStatus.latency` with the measured round-trip.
  ///
  /// Routes through ``_push`` with `lazyConnect: false`: a dead socket must surface as a
  /// `.disconnected`/timeout (→ `onConnectionLost`) rather than trigger a reconnect. Throws
  /// if the send fails or the reply times out, which the heartbeat loop maps to connection loss.
  func _sendHeartbeat() async throws(RealtimeError) {
    // Wall clock for round-trip measurement; scheduling/timeout uses `configuration.clock`.
    let wallClock = ContinuousClock()
    let sentAt = wallClock.now
    _ = try await _push(
      topic: "phoenix", .heartbeat, .text([:]),
      joinRef: nil, lazyConnect: false,
      ack: .require(timeout: configuration.heartbeat, error: .disconnected)
    )
    updateLatency(sentAt.duration(to: wallClock.now))
  }

  /// Updates `ConnectionStatus.latency` in-place while preserving the current state.
  private func updateLatency(_ latency: Duration) {
    let current = statusBroadcaster.current
    statusBroadcaster.emit(
      ConnectionStatus(state: current.state, since: current.since, latency: latency)
    )
    // Emit heartbeat RTT metric as a log event (spec §10 metrics-as-logs).
    log(
      .debug, .connection, "Heartbeat round-trip complete",
      metadata: ["heartbeat.rtt_ms": "\(latency.inMilliseconds)"]
    )
  }
}
