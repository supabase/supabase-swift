//
//  Broadcaster.swift
//  Realtime
//

import ConcurrencyExtras

/// Fans one writer out to any number of `AsyncStream` subscribers.
///
/// Subscribing is synchronous, so a stream taken before a command sees every element the command
/// causes. A broadcaster made with ``init(retaining:)`` is state-like: a new subscriber first
/// receives the current value, if there is one.
///
/// Continuations are resumed outside the lock, because finishing one runs its `onTermination`
/// handler synchronously and that handler takes the lock to unregister.
final class Broadcaster<Element: Sendable>: Sendable {
  private struct Subscriber: Sendable {
    let filter: (@Sendable (Element) -> Bool)?
    let continuation: AsyncStream<Element>.Continuation
  }

  private struct State: Sendable {
    var subscribers: [UInt64: Subscriber] = [:]
    var nextID: UInt64 = 0
    var retained: Element?
    var retains: Bool
    var finished = false
  }

  private let state: LockIsolated<State>

  /// An event stream: subscribers see only the elements yielded after they subscribe.
  init() {
    state = LockIsolated(State(retains: false))
  }

  /// A state stream: subscribers first receive the latest element, or `initial` before the first yield.
  init(retaining initial: Element?) {
    state = LockIsolated(State(retained: initial, retains: true))
  }

  /// The latest element of a state stream, or `nil` for an event stream.
  var current: Element? {
    state.withValue { $0.retained }
  }

  var subscriberCount: Int {
    state.withValue { $0.subscribers.count }
  }

  var isFinished: Bool {
    state.withValue { $0.finished }
  }

  /// Returns a stream of the elements yielded from now on, preceded by the retained element if any.
  ///
  /// `filter` applies to yielded elements only; the retained element is always replayed.
  /// `onTermination` runs once when the stream ends, by cancellation or by ``finish()``.
  func subscribe(
    bufferingPolicy: AsyncStream<Element>.Continuation.BufferingPolicy = .unbounded,
    where filter: (@Sendable (Element) -> Bool)? = nil,
    onTermination: (@Sendable () -> Void)? = nil
  ) -> AsyncStream<Element> {
    let (stream, continuation) = AsyncStream.makeStream(
      of: Element.self, bufferingPolicy: bufferingPolicy)
    let alreadyFinished = state.withValue { state in
      // Yielded under the lock so a concurrent `yield` cannot overtake the retained element.
      if let retained = state.retained { continuation.yield(retained) }
      guard !state.finished else {
        continuation.onTermination = { _ in onTermination?() }
        return true
      }
      state.nextID += 1
      let id = state.nextID
      continuation.onTermination = { [weak self] _ in
        self?.remove(id)
        onTermination?()
      }
      state.subscribers[id] = Subscriber(filter: filter, continuation: continuation)
      return false
    }
    if alreadyFinished { continuation.finish() }
    return stream
  }

  /// Delivers `element` to every matching subscriber. Ignored once finished.
  func yield(_ element: Element) {
    let targets = state.withValue { state -> [AsyncStream<Element>.Continuation] in
      guard !state.finished else { return [] }
      if state.retains { state.retained = element }
      return state.subscribers.values.compactMap { subscriber in
        (subscriber.filter?(element) ?? true) ? subscriber.continuation : nil
      }
    }
    for continuation in targets { continuation.yield(element) }
  }

  /// Finishes every stream. Later subscribers get the retained element, then an immediate finish.
  func finish() {
    let continuations = state.withValue { state -> [AsyncStream<Element>.Continuation] in
      state.finished = true
      defer { state.subscribers = [:] }
      return state.subscribers.values.map(\.continuation)
    }
    for continuation in continuations { continuation.finish() }
  }

  private func remove(_ id: UInt64) {
    state.withValue { $0.subscribers[id] = nil }
  }
}
