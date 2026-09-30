//
//  Task+withTimeout.swift
//
//
//  Created by Guilherme Souza on 19/04/24.
//

package import Foundation

@discardableResult
package func withTimeout<R: Sendable>(
  interval: TimeInterval,
  clock: any Clock<Duration> = ContinuousClock(),
  @_inheritActorContext operation: @escaping @Sendable () async throws -> R
) async throws -> R {
  try await withThrowingTaskGroup(of: R.self) { group in
    defer {
      group.cancelAll()
    }

    let deadline = Date(timeIntervalSinceNow: interval)

    group.addTask {
      try await operation()
    }

    group.addTask {
      let interval = deadline.timeIntervalSinceNow
      if interval > 0 {
        try await clock.sleep(for: .seconds(interval))
      }
      try Task.checkCancellation()
      throw TimeoutError()
    }

    // Two tasks were just added, so `next()` always has one to return. Treat an empty group as a
    // timeout rather than trapping.
    guard let result = try await group.next() else {
      throw TimeoutError()
    }
    return result
  }
}

package struct TimeoutError: Error, Hashable {}
