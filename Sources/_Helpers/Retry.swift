//
//  Retry.swift
//
//
//  Created by Guilherme Souza on 20/05/24.
//

import Foundation

package struct RetryLimitReachedError: Error {}

package enum DelayStrategy {
  case constant(TimeInterval)
  case backoff(base: UInt = 2, scale: Double = 0.5)

  func timeInterval(for attempt: Int) -> TimeInterval {
    switch self {
    case let .constant(timeInterval):
      timeInterval

    case let .backoff(base, scale):
      pow(Double(base), Double(attempt)) * scale
    }
  }
}

/// Retry an operation while `limit` is not reached with a `delay` between retries.
package func retry<T>(
  limit: Int = 3,
  delay: DelayStrategy = .backoff(),
  _ operation: @Sendable (_ attempt: Int) async throws -> T
) async throws -> T {
  for attempt in 0 ..< limit {
    do {
      return try await operation(attempt)
    } catch {
      if error.isRetryable {
        try await Task.sleep(nanoseconds: NSEC_PER_SEC * UInt64(delay.timeInterval(for: attempt)))
      } else {
        throw error
      }
    }
  }

  throw RetryLimitReachedError()
}
