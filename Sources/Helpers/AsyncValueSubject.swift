//
//  AsyncValueSubject.swift
//  Supabase
//
//  Created by Guilherme Souza on 31/10/24.
//

import ConcurrencyExtras
import Foundation

/// A thread-safe subject that wraps a single value and provides async access to its updates.
/// Similar to Combine's CurrentValueSubject, but designed for async/await usage.
package final class AsyncValueSubject<Value: Sendable>: Sendable {

  /// Defines how values are buffered in the underlying AsyncStream.
  package typealias BufferingPolicy = AsyncStream<Value>.Continuation.BufferingPolicy

  /// Internal state container for the subject.
  struct MutableState {
    var value: Value
    var continuations: [UInt: AsyncStream<Value>.Continuation] = [:]
    var count: UInt = 0
  }

  let bufferingPolicy: BufferingPolicy
  let mutableState: LockIsolated<MutableState>

  /// Creates a new AsyncValueSubject with an initial value.
  /// - Parameters:
  ///   - initialValue: The initial value to store
  ///   - bufferingPolicy: Determines how values are buffered in the AsyncStream (defaults to .unbounded)
  package init(_ initialValue: Value, bufferingPolicy: BufferingPolicy = .unbounded) {
    self.mutableState = LockIsolated(MutableState(value: initialValue))
    self.bufferingPolicy = bufferingPolicy
  }

  deinit {
    finish()
  }

  /// The current value stored in the subject.
  package var value: Value {
    mutableState.value
  }

  /// Sends a new value to the subject and notifies all observers.
  /// - Parameter value: The new value to send
  package func yield(_ value: Value) {
    mutableState.withValue {
      $0.value = value

      for (_, continuation) in $0.continuations {
        continuation.yield(value)
      }
    }
  }

  /// Resume the task awaiting the next iteration point by having it return
  /// nil, which signifies the end of the iteration.
  ///
  /// Calling this function more than once has no effect. After calling
  /// finish, the stream enters a terminal state and doesn't produce any
  /// additional elements.
  package func finish() {
    for (_, continuation) in mutableState.continuations {
      continuation.finish()
    }
  }

  /// An AsyncStream that emits the current value and all subsequent updates.
  package var values: AsyncStream<Value> {
    AsyncStream(bufferingPolicy: bufferingPolicy) { continuation in
      insert(continuation)
    }
  }

  /// Observes changes to the subject's value by executing the provided handler.
  /// - Parameters:
  ///   - priority: The priority of the task that will observe changes (optional)
  ///   - handler: A closure that will be called with each new value
  /// - Returns: A task that can be cancelled to stop observing changes
  @discardableResult
  package func onChange(
    priority: TaskPriority? = nil,
    _ handler: @escaping @Sendable (Value) -> Void
  ) -> Task<Void, Never> {
    let stream = self.values
    return Task(priority: priority) {
      for await value in stream {
        if Task.isCancelled {
          break
        }
        handler(value)
      }
    }
  }

  /// Adds a new continuation to the subject and yields the current value.
  private func insert(_ continuation: AsyncStream<Value>.Continuation) {
    mutableState.withValue { state in
      continuation.yield(state.value)
      let id = state.count + 1
      state.count = id
      state.continuations[id] = continuation

      continuation.onTermination = { [weak self] _ in
        self?.remove(continuation: id)
      }
    }
  }

  /// Removes a continuation when it's terminated.
  private func remove(continuation id: UInt) {
    mutableState.withValue {
      _ = $0.continuations.removeValue(forKey: id)
    }
  }
}

extension AsyncValueSubject where Value == Void {
  package func yield() {
    self.yield(())
  }
}
