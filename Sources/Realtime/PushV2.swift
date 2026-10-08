//
//  PushV2.swift
//
//
//  Created by Guilherme Souza on 02/01/24.
//

import Foundation
import Logging

/// The server's reply status to a push, or ``timeout`` when no reply arrived in time.
///
/// A reply status this SDK has no member for is preserved in ``rawValue``.
public struct PushStatus: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
  public let rawValue: String

  /// Creates a ``PushStatus`` from a raw string value.
  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// Creates a ``PushStatus`` from a string literal.
  public init(stringLiteral value: String) {
    self.init(rawValue: value)
  }

  /// The server acknowledged the push.
  public static let ok: PushStatus = "ok"

  /// The server rejected the push.
  public static let error: PushStatus = "error"

  /// No reply arrived within the configured timeout interval.
  public static let timeout: PushStatus = "timeout"
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
      return .ok
    }

    do {
      return try await withTimeout(
        channel.socket.options.timeout, clock: channel.socket.clock
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
