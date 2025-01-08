//
//  Task+withTimeout.swift
//
//
//  Created by Guilherme Souza on 19/04/24.
//

import Foundation

@discardableResult
package func withTimeout<R: Sendable>(
  interval: TimeInterval,
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
        try await _clock.sleep(for: interval)
      }
      try Task.checkCancellation()
      throw TimeoutError()
    }

    return try await group.next()!
  }
}

package struct TimeoutError: Error, Hashable {}
