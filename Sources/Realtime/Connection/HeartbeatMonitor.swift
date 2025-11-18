//
//  HeartbeatMonitor.swift
//  Realtime
//
//  Created on 17/01/25.
//

import Foundation
import Helpers

/// Manages heartbeat send/receive cycle with timeout detection.
///
/// This actor encapsulates all heartbeat logic, ensuring that heartbeats are sent
/// at regular intervals and timeouts are detected when responses aren't received.
actor HeartbeatMonitor {
  // MARK: - Properties

  private let interval: TimeInterval
  private let refGenerator: @Sendable () -> String
  private let sendHeartbeat: @Sendable (String) async -> Void
  private let onTimeout: @Sendable () async -> Void
  private let logger: (any SupabaseLogger)?

  private var monitorTask: Task<Void, Never>?
  private var pendingRef: String?

  // MARK: - Initialization

  init(
    interval: TimeInterval,
    refGenerator: @escaping @Sendable () -> String,
    sendHeartbeat: @escaping @Sendable (String) async -> Void,
    onTimeout: @escaping @Sendable () async -> Void,
    logger: (any SupabaseLogger)?
  ) {
    self.interval = interval
    self.refGenerator = refGenerator
    self.sendHeartbeat = sendHeartbeat
    self.onTimeout = onTimeout
    self.logger = logger
  }

  // MARK: - Public API

  /// Start heartbeat monitoring.
  ///
  /// Sends heartbeats at regular intervals and detects timeouts when responses
  /// aren't received before the next interval.
  func start() {
    stop() // Cancel any existing monitor

    logger?.debug("Starting heartbeat monitor with interval: \(interval)")

    monitorTask = Task {
      while !Task.isCancelled {
        do {
          try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        } catch {
          // Task cancelled during sleep
          break
        }

        if Task.isCancelled { break }

        await sendNextHeartbeat()
      }

      logger?.debug("Heartbeat monitor stopped")
    }
  }

  /// Stop heartbeat monitoring.
  func stop() {
    if monitorTask != nil {
      logger?.debug("Stopping heartbeat monitor")
      monitorTask?.cancel()
      monitorTask = nil
      pendingRef = nil
    }
  }

  /// Called when heartbeat response is received.
  ///
  /// - Parameter ref: The reference ID from the heartbeat response
  func onHeartbeatResponse(ref: String) {
    guard let pending = pendingRef, pending == ref else {
      logger?.debug("Received heartbeat response with mismatched ref: \(ref)")
      return
    }

    logger?.debug("Heartbeat acknowledged: \(ref)")
    pendingRef = nil
  }

  // MARK: - Private Helpers

  private func sendNextHeartbeat() async {
    // Check if previous heartbeat was acknowledged
    if let pending = pendingRef {
      logger?.debug("Heartbeat timeout - previous heartbeat not acknowledged: \(pending)")
      pendingRef = nil
      await onTimeout()
      return
    }

    // Send new heartbeat
    let ref = refGenerator()
    pendingRef = ref

    logger?.debug("Sending heartbeat: \(ref)")
    await sendHeartbeat(ref)
  }
}
