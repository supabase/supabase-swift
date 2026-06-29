//
//  ReconnectionPolicy.swift
//  RealtimeV3
//
//  Created by Guilherme Souza on 29/06/26.
//

import Foundation

/// Determines when and whether to reconnect after a disconnection.
public struct ReconnectionPolicy: Sendable {
  /// Returns the delay before the next reconnection attempt, or `nil` to give up.
  ///
  /// - Parameters:
  ///   - attempt: The zero-based reconnection attempt number.
  ///   - lastError: The error that caused the disconnection.
  /// - Returns: The delay to wait before the next attempt, or `nil` to give up.
  public var nextDelay:
    @Sendable (
      _ attempt: Int,
      _ lastError: any Error & Sendable
    ) -> Duration?

  /// Never reconnects — always returns `nil`.
  public static let never: Self = Self { _, _ in nil }

  /// Exponential backoff with optional jitter.
  ///
  /// - Parameters:
  ///   - initial: The delay for attempt 0.
  ///   - max: The maximum delay (clamped).
  ///   - jitter: Fractional jitter applied deterministically based on attempt number (0 = no jitter).
  public static func exponentialBackoff(
    initial: Duration,
    max: Duration,
    jitter: Double = 0.2
  ) -> Self {
    Self { attempt, _ in
      // Compute base: initial * 2^attempt, clamped to max
      let multiplier = Double(1 << min(attempt, 62))
      let initialSeconds =
        Double(initial.components.seconds)
        + Double(initial.components.attoseconds) * 1e-18
      let baseSeconds = min(
        initialSeconds * multiplier,
        Double(max.components.seconds)
          + Double(max.components.attoseconds) * 1e-18)

      // Apply deterministic jitter derived from attempt (no random, no Date).
      // jitter:0 produces no adjustment; jitter>0 varies ±jitter based on attempt parity.
      let jitterFraction: Double
      if jitter == 0 {
        jitterFraction = 0
      } else {
        // Deterministic: odd attempts subtract jitter/2, even attempts add jitter/2
        jitterFraction = attempt % 2 == 0 ? jitter / 2 : -(jitter / 2)
      }
      let finalSeconds = baseSeconds * (1 + jitterFraction)
      let nanoseconds = Int64(finalSeconds * 1_000_000_000)
      return .nanoseconds(nanoseconds)
    }
  }

  /// Fixed delay with an optional maximum number of attempts.
  ///
  /// - Parameters:
  ///   - delay: The fixed delay between attempts.
  ///   - maxAttempts: Maximum number of attempts. `nil` means unlimited.
  public static func fixed(_ delay: Duration, maxAttempts: Int?) -> Self {
    Self { attempt, _ in
      if let max = maxAttempts, attempt >= max {
        return nil
      }
      return delay
    }
  }
}
