//
//  Task+withTimeout.swift
//
//
//  Created by Guilherme Souza on 19/04/24.
//

@discardableResult
package func withTimeout<R: Sendable>(
  _ duration: Duration,
  clock: any Clock<Duration> = ContinuousClock(),
  @_inheritActorContext operation: @escaping @Sendable @concurrent () async throws -> R
) async throws -> R {
  try await withThrowingTaskGroup(of: R.self) { group in
    defer {
      group.cancelAll()
    }

    group.addTask {
      try await operation()
    }

    group.addTask {
      if duration > .zero {
        try await clock.sleep(for: duration)
      }
      try Task.checkCancellation()
      throw TimeoutError()
    }

    guard let result = try await group.next() else {
      throw TimeoutError()
    }
    return result
  }
}

package struct TimeoutError: Error, Hashable {}
