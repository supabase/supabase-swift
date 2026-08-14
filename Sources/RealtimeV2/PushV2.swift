//
//  PushV2.swift
//
//
//  Created by Guilherme Souza on 02/01/24.
//

import Foundation
import Logging

/// Represents the different status of a push
public enum PushStatus: String, Sendable {
  case ok
  case error
  case timeout
}

@MainActor
final class PushV2 {
  private weak var channel: (any RealtimeChannelProtocol)?
  let message: RealtimeMessageV2

  private var receivedContinuation: CheckedContinuation<PushStatus, Never>?
  /// Buffers a status delivered via ``didReceive(status:)`` before ``send()`` has
  /// registered its continuation, so an ack that arrives early isn't dropped.
  private var receivedStatus: PushStatus?

  init(channel: (any RealtimeChannelProtocol)?, message: RealtimeMessageV2) {
    self.channel = channel
    self.message = message
  }

  func send() async -> PushStatus {
    guard let channel = channel else {
      return .error
    }

    channel.socket.push(message)

    if !channel.config.broadcast.acknowledgeBroadcasts {
      // channel was configured with `ack = false`,
      // don't wait for a response and return `ok`.
      return .ok
    }

    do {
      return try await withTimeout(
        interval: channel.socket.options.timeoutInterval, clock: channel.socket.clock
      ) {
        await withCheckedContinuation { continuation in
          if let status = self.receivedStatus {
            self.receivedStatus = nil
            continuation.resume(returning: status)
          } else {
            self.receivedContinuation = continuation
          }
        }
      }
    } catch is TimeoutError {
      channel.logger.debug("Push timed out.")
      return .timeout
    } catch {
      channel.logger.error("Error sending push: \(error.localizedDescription)")
      return .error
    }
  }

  func didReceive(status: PushStatus) {
    if let receivedContinuation {
      receivedContinuation.resume(returning: status)
      self.receivedContinuation = nil
    } else {
      // The ack arrived before `send()` registered its continuation; buffer it
      // so `send()` can resume immediately instead of timing out.
      receivedStatus = status
    }
  }
}
