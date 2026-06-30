//
//  Realtime+Reconnection.swift
//  RealtimeV3
//
//  Created by Guilherme Souza on 29/06/26.
//

import Clocks
import Foundation

// MARK: - Connection loss + reconnection

extension Realtime {
  /// Connection-loss handler with automatic reconnection.
  ///
  /// When `intentionalDisconnect` is false (the default), this drives the reconnection
  /// loop: it consults `configuration.reconnection.nextDelay`, sleeps on
  /// `configuration.clock`, and retries `transport.connect` until success or the
  /// policy returns `nil` (give up).
  ///
  /// Idempotency: re-entry is prevented by the `connection == nil` guard at the top of
  /// this function. The guard atomically claims and clears the connection reference before
  /// any suspension point, so a concurrent or re-entrant call (e.g. both the frame-routing
  /// stream and the heartbeat firing almost simultaneously) will see `connection == nil`
  /// and return immediately, preventing overlapping cleanup or reconnection loops.
  ///
  /// `isReconnecting` is reserved for Task 14 (disconnect()/state introspection) and is
  /// NOT the idempotency mechanism.
  func handleConnectionLost(_ error: RealtimeError) async {
    // Atomically claim and clear the connection reference before any suspension point.
    // This is the single-ownership guard: any concurrent or re-entrant call will see
    // connection == nil and return immediately, preventing overlapping cleanup or
    // reconnection loops.
    guard let lostConnection = connection else { return }
    connection = nil

    // Cancel background tasks.
    heartbeatTask?.cancel()
    heartbeatTask = nil
    routingTask?.cancel()
    routingTask = nil

    // Fail all pending pushes so callers don't hang indefinitely.
    await inflightPushRegistry.failAll(error)

    // Close the connection we captured above.
    await lostConnection.close(code: 1001, reason: "connection lost")

    // If the disconnect was intentional (set by disconnect()), stay closed.
    // Do NOT overwrite .closed(.clientDisconnected) and do NOT trigger reconnection.
    if intentionalDisconnect {
      return
    }

    // If the socket was closed by the idle-close timer, suppress reconnection.
    // The idle close already transitioned status to .idle and cleared the connection.
    // A future connect() call (from subscribe()) will re-open the socket.
    if idleClosed {
      return
    }

    // Spawn reconnection as an unstructured Task so it runs independently of the routing
    // task (which may be the caller and may be cancelled). The reconnection loop must NOT
    // inherit cancellation from the routing task — it needs to outlive it.
    reconnectTask = Task {
      await runReconnectionLoop(initialError: error)
    }
  }

  /// Reconnection loop. Runs in its own unstructured Task so it is not affected by the
  /// cancellation of the routing task that detected the connection loss.
  private func runReconnectionLoop(initialError: RealtimeError) async {
    isReconnecting = true
    // Clear reconnectTask on ALL exit paths (success, give-up, cancellation) so Task 14
    // can reliably check `reconnectTask == nil` to determine whether reconnection is in progress.
    defer {
      isReconnecting = false
      reconnectTask = nil
    }

    var attempt = 1
    var lastError: any Error & Sendable = initialError

    while true {
      // Consult the policy for the delay before this attempt.
      guard let delay = configuration.reconnection.nextDelay(attempt, lastError) else {
        // Policy says give up: fail all (in case new pushes arrived), go to closed.
        await inflightPushRegistry.failAll(initialError)
        transition(to: .closed(.transportFailure))
        // Terminate all eligible channels so their streams throw/finish (Task 29).
        await terminateChannelsOnGiveUp()
        return
      }

      // Signal reconnecting.
      log(
        .info, .connection, "Reconnecting to Realtime server",
        metadata: ["reconnect.attempt": "\(attempt)"]
      )
      transition(to: .reconnecting(attempt: attempt, lastError: lastError))

      // Wait the backoff delay on the configured clock.
      do {
        try await configuration.clock.sleep(for: delay)
      } catch {
        // CancellationError: actor is being torn down — exit silently.
        return
      }

      // Attempt to reconnect.
      do {
        let conn = try await _openConnection()
        // Successfully reconnected: bind fresh tasks to the new connection.
        // (reconnectTask is cleared by the defer at the top of this function.)
        connection = conn
        log(.info, .connection, "Reconnected to Realtime server")
        transition(to: .connected)
        startConnectionTasks(connection: conn)
        // Re-join eligible channels (Task 29).
        await rejoinEligibleChannels()
        return
      } catch {
        // Reconnect attempt failed — record and loop.
        log(.warn, .connection, "Reconnect attempt \(attempt) failed: \(error)")
        lastError = error
        attempt += 1
      }
    }
  }

  // MARK: - Channel rejoin on reconnect (Task 29)

  /// Re-joins all channels that were previously joined and not explicitly left by the user.
  ///
  /// Called after every successful reconnect. Channels with `shouldRejoin == true` are
  /// eligible (they were transport-dropped, not user-left). Each channel's existing streams
  /// (messages, broadcasts, postgres, presence) stay open across the gap — only the
  /// `phx_join` handshake is re-sent.
  ///
  /// Channels are re-joined concurrently so a slow join on one topic does not block others.
  private func rejoinEligibleChannels() async {
    // Snapshot the full channel list. We check eligibility per-channel (actor hop).
    let allChannels = Array(channels.values)
    guard !allChannels.isEmpty else { return }

    // Re-join concurrently. Each channel's rejoin() checks its own shouldRejoin flag
    // at the start and is a no-op if not eligible.
    await withTaskGroup(of: Void.self) { group in
      for channel in allChannels {
        group.addTask {
          // Only rejoin if this channel was previously joined (actor-isolated read).
          guard await channel.shouldRejoin else { return }
          await channel.rejoin()
        }
      }
    }
  }

  /// Terminates all eligible channels when the reconnection policy gives up.
  ///
  /// Called from the give-up path in `runReconnectionLoop`. For each channel with
  /// `shouldRejoin == true`, transitions it to `.closed(.transportFailure)`, which
  /// cascades stream terminations via the existing `transition(to:)` logic.
  /// Those channels are then evicted from the registry.
  private func terminateChannelsOnGiveUp() async {
    // Snapshot topic+channel pairs. We check eligibility per-channel (actor hop).
    let snapshot = Array(channels)
    var toEvict: [String] = []
    for (topic, channel) in snapshot {
      if await channel.shouldRejoin {
        await channel.transition(to: .closed(.transportFailure))
        toEvict.append(topic)
      }
    }
    for topic in toEvict {
      channels.removeValue(forKey: topic)
    }
  }
}
