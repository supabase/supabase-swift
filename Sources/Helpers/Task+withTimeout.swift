//
//  Task+withTimeout.swift
//
//
//  Created by Guilherme Souza on 19/04/24.
//

/// Runs `body` and throws ``TimeoutError`` if it has not finished after `duration` on `clock`.
///
/// `body` runs on the caller's actor and may capture non-`Sendable` values: it is called exactly
/// once, from one child task, and the result crosses back to the caller only after that task has
/// finished. The loser of the race is cancelled, so a body that wins late sees `Task.isCancelled`.
@discardableResult
package func withTimeout<Result>(
  _ duration: Duration,
  clock: any Clock<Duration> = ContinuousClock(),
  body: () async throws -> Result
) async throws -> Result {
  // Safe: `body` is invoked once, from a single child task, and `result` is written by that task
  // and read only after the group has finished it.
  nonisolated(unsafe) let body = body
  nonisolated(unsafe) var result: Result?
  let sendableBody: @Sendable () async throws -> Void = { result = try await body() }
  try await withoutActuallyEscaping(sendableBody) { sendableBody in
    try await withThrowingTaskGroup(of: Void.self) { group in
      defer { group.cancelAll() }

      group.addTask {
        try await sendableBody()
      }

      group.addTask {
        if duration > .zero {
          try await clock.sleep(for: duration)
        }
        try Task.checkCancellation()
        throw TimeoutError()
      }

      // Two tasks were just added, so `next()` has one to return: the body (done, or failed) or
      // the timer (always a throw). An empty group cannot happen; treat it as a timeout anyway
      // rather than trapping.
      guard try await group.next() != nil else {
        throw TimeoutError()
      }
    }
  }
  // The body child finished without throwing, so it stored its result.
  return result!
}

package struct TimeoutError: Error, Hashable {}
