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
    var finished = false
  }

  let bufferingPolicy: UncheckedSendable<BufferingPolicy>
  let mutableState: LockIsolated<MutableState>

  /// Creates a new AsyncValueSubject with an initial value.
  /// - Parameters:
  ///   - initialValue: The initial value to store
  ///   - bufferingPolicy: Determines how values are buffered in the AsyncStream (defaults to .unbounded)
  package init(_ initialValue: Value, bufferingPolicy: BufferingPolicy = .unbounded) {
    self.mutableState = LockIsolated(MutableState(value: initialValue))
    self.bufferingPolicy = UncheckedSendable(bufferingPolicy)
  }

  deinit {
    finish()
  }

  /// The current value stored in the subject.
  package var value: Value {
    mutableState.value
  }

  /// Resume the task awaiting the next iteration point by having it return normally from its suspension point with a given element.
  /// - Parameter value: The value to yield from the continuation.
  ///
  /// If nothing is awaiting the next value, this method attempts to buffer the result’s element.
  ///
  /// This can be called more than once and returns to the caller immediately without blocking for any awaiting consumption from the iteration.
  package func yield(_ value: Value) {
    // Snapshot the continuations under the lock, then resume them outside of it.
    // Resuming a continuation can synchronously reach into the Swift runtime's
    // task status-record lock; holding our own lock at the same time inverts
    // lock order with cancellation (which takes the status-record lock first,
    // then calls back into `remove`/`insert`), causing a deadlock.
    let continuations: [AsyncStream<Value>.Continuation] = mutableState.withValue {
      guard !$0.finished else { return [] }

      $0.value = value
      return Array($0.continuations.values)
    }
    for continuation in continuations {
      continuation.yield(value)
    }
  }

  /// Resume the task awaiting the next iteration point by having it return
  /// nil, which signifies the end of the iteration.
  ///
  /// Calling this function more than once has no effect. After calling
  /// finish, the stream enters a terminal state and doesn't produce any
  /// additional elements.
  package func finish() {
    // See the comment in `yield` for why continuations must be resumed
    // outside of the lock.
    let continuations: [AsyncStream<Value>.Continuation] = mutableState.withValue {
      guard $0.finished == false else { return [] }

      $0.finished = true
      return Array($0.continuations.values)
    }
    for continuation in continuations {
      continuation.finish()
    }
  }

  /// An AsyncStream that emits the current value and all subsequent updates.
  package var values: AsyncStream<Value> {
    AsyncStream(bufferingPolicy: bufferingPolicy.value) { continuation in
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
    // See the comment in `yield` for why continuations must be resumed
    // outside of the lock.
    let (id, currentValue) = mutableState.withValue { state -> (UInt, Value) in
      let id = state.count + 1
      state.count = id
      state.continuations[id] = continuation
      return (id, state.value)
    }

    continuation.onTermination = { [weak self] _ in
      self?.remove(continuation: id)
    }
    continuation.yield(currentValue)
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
