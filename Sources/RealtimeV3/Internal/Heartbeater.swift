//
//  Heartbeater.swift
//  RealtimeV3
//
//  Created by Guilherme Souza on 29/06/26.
//

import Clocks
import Foundation

/// Drives the periodic heartbeat for an active WebSocket connection.
///
/// The loop sleeps `heartbeat` on `clock`, then invokes `beat` — which sends the heartbeat
/// frame and awaits its reply via `Realtime._sendHeartbeat()`. If `beat` throws (send failure
/// or reply timeout), `onConnectionLost` is called so the actor can react.
///
/// Start one instance after a successful `connect()` and cancel its task on disconnect.
struct Heartbeater: Sendable {
  typealias Beat = @Sendable () async throws -> Void
  typealias OnConnectionLost = @Sendable (RealtimeError) async -> Void

  private let heartbeat: Duration
  private let clock: any Clock<Duration> & Sendable
  private let beat: Beat
  private let onConnectionLost: OnConnectionLost

  init(
    heartbeat: Duration,
    clock: any Clock<Duration> & Sendable,
    beat: @escaping Beat,
    onConnectionLost: @escaping OnConnectionLost
  ) {
    self.heartbeat = heartbeat
    self.clock = clock
    self.beat = beat
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

      do {
        try await beat()
      } catch let error as RealtimeError {
        await onConnectionLost(error)
      } catch {
        await onConnectionLost(.cancelled)
      }
    }
  }
}
