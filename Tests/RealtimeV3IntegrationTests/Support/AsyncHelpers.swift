//
//  AsyncHelpers.swift
//  RealtimeV3IntegrationTests
//
//  Created by Guilherme Souza on 29/06/26.
//

import Foundation

/// Waits for the first element of `stream` that satisfies `predicate`, with a timeout.
///
/// - Parameters:
///   - stream: An `AsyncStream` to consume.
///   - timeout: Maximum wall-clock duration to wait.
///   - description: Human-readable description used in the timeout error message.
///   - predicate: Returns `true` when the desired element has arrived.
/// - Throws: `TimeoutError` if `timeout` elapses before `predicate` returns `true`.
func waitFor<T: Sendable>(
  _ stream: AsyncStream<T>,
  timeout: Duration = .seconds(10),
  description: String,
  where predicate: @Sendable @escaping (T) -> Bool
) async throws {
  try await withThrowingTaskGroup(of: Void.self) { group in
    group.addTask {
      for await value in stream {
        if predicate(value) { return }
      }
    }
    group.addTask {
      try await Task.sleep(for: timeout)
      throw TimeoutError(description: description, timeout: timeout)
    }
    // Take the first result — either the predicate matched or we timed out.
    try await group.next()
    group.cancelAll()
  }
}

struct TimeoutError: Error, CustomStringConvertible {
  let description: String
  let timeout: Duration

  var localizedDescription: String {
    "Timed out waiting for '\(description)' after \(timeout)"
  }
}
