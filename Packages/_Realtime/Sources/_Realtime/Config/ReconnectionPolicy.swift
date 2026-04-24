import Foundation

public struct ReconnectionPolicy: Sendable {
  /// Return `nil` to stop retrying.
  public var nextDelay: @Sendable (_ attempt: Int, _ lastError: any Error & Sendable) -> Duration?

  public static let never = ReconnectionPolicy { _, _ in nil }

  public static func exponentialBackoff(
    initial: Duration,
    max: Duration,
    jitter: Double = 0.2
  ) -> ReconnectionPolicy {
    let initialSecs = Double(initial.components.seconds)
    let maxSecs = Double(max.components.seconds)
    return ReconnectionPolicy { attempt, _ in
      let base = initialSecs * pow(2.0, Double(attempt - 1))
      let capped = Swift.min(base, maxSecs)
      let noise = capped * Double.random(in: -jitter...jitter)
      return .seconds(Swift.max(0, capped + noise))
    }
  }

  public static func fixed(_ delay: Duration, maxAttempts: Int? = nil) -> ReconnectionPolicy {
    ReconnectionPolicy { attempt, _ in
      if let max = maxAttempts, attempt > max { return nil }
      return delay
    }
  }
}
