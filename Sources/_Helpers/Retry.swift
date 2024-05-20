//
//  Retry.swift
//
//
//  Created by Guilherme Souza on 20/05/24.
//

import Foundation

package struct RetryLimitReachedError: Error {}

/// Retry an operation while `limit` is not reached and `isRetryable` returns true.
package func retry<T>(
  limit: Int = .max,
  _ operation: @Sendable (_ attempt: Int) async throws -> T,
  isRetryable: @Sendable (_ attempt: Int, _ error: any Error) -> Bool
) async throws -> T {
  for attempt in 0 ..< limit {
    do {
      return try await operation(attempt)
    } catch {
      if !isRetryable(attempt, error) {
        throw error
      }
    }
  }

  throw RetryLimitReachedError()
}
