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
  private struct MutableState {
    var value: Value
    var continuations: [UInt: AsyncStream<Value>.Continuation] = [:]
    var count: UInt = 0
    var finished = false
    /// Monotonic counter handed out under this same lock, so its order always
    /// matches the order `yield`/`finish`/subscribe calls were serialized in.
    /// Used by `deliveryOrder` to resume continuations in that same order,
    /// even though the resume itself happens outside this lock.
    var nextTicket: UInt = 0
  }

  private let bufferingPolicy: UncheckedSendable<BufferingPolicy>
  private let mutableState: LockIsolated<MutableState>

  /// Delivers continuation resumes in the exact order their tickets were
  /// handed out — see `deliver(ticket:)`.
  private let deliveryOrder = TicketTurnstile()

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
    guard
      let (ticket, continuations) = mutableState.withValue({
        state -> (UInt, [AsyncStream<Value>.Continuation])? in
        guard !state.finished else { return nil }
        state.value = value
        let ticket = state.nextTicket
        state.nextTicket += 1
        return (ticket, Array(state.continuations.values))
      })
    else { return }

    deliveryOrder.deliver(ticket: ticket) {
      for continuation in continuations {
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
    guard
      let (ticket, continuations) = mutableState.withValue({
        state -> (UInt, [AsyncStream<Value>.Continuation])? in
        guard !state.finished else { return nil }
        state.finished = true
        let ticket = state.nextTicket
        state.nextTicket += 1
        return (ticket, Array(state.continuations.values))
      })
    else { return }

    deliveryOrder.deliver(ticket: ticket) {
      for continuation in continuations {
        continuation.finish()
      }
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
    // Taking the ticket under the same lock that registers this continuation
    // keeps the initial replay correctly ordered against concurrent
    // `yield`/`finish` calls — see `deliveryOrder`.
    let (id, ticket, currentValue) = mutableState.withValue { state -> (UInt, UInt, Value) in
      let id = state.count + 1
      state.count = id
      state.continuations[id] = continuation

      let ticket = state.nextTicket
      state.nextTicket += 1
      return (id, ticket, state.value)
    }

    continuation.onTermination = { [weak self] _ in
      self?.remove(continuation: id)
    }

    deliveryOrder.deliver(ticket: ticket) {
      continuation.yield(currentValue)
    }
  }

  /// Removes a continuation when it's terminated.
  private func remove(continuation id: UInt) {
    mutableState.withValue {
      _ = $0.continuations.removeValue(forKey: id)
    }
  }

  /// Resumes continuations in the exact order their tickets were handed out,
  /// without requiring the caller to hold any lock while resuming.
  ///
  /// Resuming a continuation can synchronously reach into the Swift runtime's
  /// task status-record lock. Task cancellation takes the opposite order: it
  /// holds that status-record lock first, then calls back into `remove` for
  /// `mutableState`'s lock. If a resume were performed while still holding
  /// `mutableState`'s lock, those two orders would invert and deadlock (see
  /// supabase-swift#1154). `TicketTurnstile` only ever guards the resume
  /// itself — never `mutableState` — so `remove` can never be blocked by it.
  private final class TicketTurnstile: @unchecked Sendable {
    private let condition = NSCondition()
    private var nowServing: UInt = 0

    func deliver(ticket: UInt, _ work: () -> Void) {
      condition.lock()
      while nowServing != ticket {
        condition.wait()
      }
      work()
      nowServing += 1
      condition.broadcast()
      condition.unlock()
    }
  }
}

extension AsyncValueSubject where Value == Void {
  package func yield() {
    self.yield(())
  }
}
