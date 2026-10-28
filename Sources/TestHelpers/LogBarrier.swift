//
//  LogBarrier.swift
//  TestHelpers
//

import ConcurrencyExtras
import Foundation
package import Testing
package import Logging

/// Holds the task that logs a chosen message until ``release()``, so a test can act between two
/// steps of a call that offer no other point to stop at.
///
/// A log handler is synchronous, so the held task blocks the thread it runs on. A hold that lasts
/// 10 seconds reports an issue and lets the task go, so a thread pool too small to run the test
/// meanwhile fails the test instead of deadlocking it.
package final class LogBarrier: Sendable {
  private struct State {
    var target: (message: String, function: String?, sourceLocation: SourceLocation)?
    var hasArrived = false
    var watcher: CheckedContinuation<Void, Never>?
  }

  package struct Handler: LogHandler {
    let barrier: LogBarrier
    package var metadata: Logging.Logger.Metadata = [:]
    package var logLevel: Logging.Logger.Level = .trace

    package init(barrier: LogBarrier) {
      self.barrier = barrier
    }

    package subscript(metadataKey key: String) -> Logging.Logger.Metadata.Value? {
      get { metadata[key] }
      set { metadata[key] = newValue }
    }

    package func log(
      level: Logging.Logger.Level,
      message: Logging.Logger.Message,
      metadata: Logging.Logger.Metadata?,
      source: String,
      file: String,
      function: String,
      line: UInt
    ) {
      barrier.logged(message.description, in: function)
    }
  }

  private let state = LockIsolated(State())
  private let released = DispatchSemaphore(value: 0)

  package init() {}

  /// Holds the next task that logs `message`, from `function` when it is not `nil`.
  package func hold(
    on message: String, in function: String? = nil,
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    state.withValue { $0.target = (message, function, sourceLocation) }
  }

  /// Returns once a task is held, or once the waiting task is cancelled.
  package func arrival() async {
    await withTaskCancellationHandler {
      await withCheckedContinuation { watcher in
        let isWaiting = state.withValue { state in
          // A cancel that lands before this point finds nothing to resume.
          guard !state.hasArrived, !Task.isCancelled else { return false }
          state.watcher = watcher
          return true
        }
        if !isWaiting { watcher.resume() }
      }
    } onCancel: {
      state.withValue { state in
        defer { state.watcher = nil }
        return state.watcher
      }?.resume()
    }
  }

  /// Lets the held task go.
  package func release() {
    released.signal()
  }

  private func logged(_ message: String, in function: String) {
    let held = state.withValue {
      state -> (sourceLocation: SourceLocation, watcher: CheckedContinuation<Void, Never>?)? in
      guard let target = state.target, target.message == message,
        target.function == nil || target.function == function
      else { return nil }
      state.target = nil
      state.hasArrived = true
      defer { state.watcher = nil }
      return (target.sourceLocation, state.watcher)
    }
    guard let held else { return }
    held.watcher?.resume()
    if released.wait(timeout: .now() + .seconds(10)) == .timedOut {
      Issue.record(
        "LogBarrier held the task that logged \"\(message)\" for 10 s with no release().",
        sourceLocation: held.sourceLocation)
    }
  }
}
