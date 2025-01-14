//
//  EventEmitter.swift
//
//
//  Created by Guilherme Souza on 08/03/24.
//

import ConcurrencyExtras
import Foundation

/// A token for cancelling observations.
///
/// When this token gets deallocated it cancels the observation it was associated with. Store this token in another object to keep the observation alive.
public final class ObservationToken: @unchecked Sendable, Hashable {
  private let _isCancelled = LockIsolated(false)
  package var onCancel: @Sendable () -> Void

  public var isCancelled: Bool {
    _isCancelled.withValue { $0 }
  }

  package init(onCancel: @escaping @Sendable () -> Void = {}) {
    self.onCancel = onCancel
  }

  @available(*, deprecated, renamed: "cancel")
  public func remove() {
    cancel()
  }

  public func cancel() {
    _isCancelled.withValue { isCancelled in
      guard !isCancelled else { return }
      defer { isCancelled = true }
      onCancel()
    }
  }

  deinit {
    cancel()
  }

  public static func == (lhs: ObservationToken, rhs: ObservationToken) -> Bool {
    lhs === rhs
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(ObjectIdentifier(self))
  }

  public func store(in collection: inout some RangeReplaceableCollection<ObservationToken>) {
    collection.append(self)
  }

  public func store(in set: inout Set<ObservationToken>) {
    set.insert(self)
  }
}

package final class EventEmitter<Event: Sendable>: Sendable {
  public typealias Listener = @Sendable (Event) -> Void

  struct MutableState {
    var listeners: [(key: ObjectIdentifier, listener: Listener)] = []
    var lastEvent: Event
  }

  let mutableState: LockIsolated<MutableState>

  /// The last event emitted by this Emiter, or the initial event.
  package var lastEvent: Event { mutableState.lastEvent }

  package let emitsLastEventWhenAttaching: Bool

  package init(
    initialEvent event: Event,
    emitsLastEventWhenAttaching: Bool = true
  ) {
    mutableState = LockIsolated(MutableState(lastEvent: event))
    self.emitsLastEventWhenAttaching = emitsLastEventWhenAttaching
  }

  /// Attaches a new listener for observing event emissions.
  ///
  /// If emitter initialized with `emitsLastEventWhenAttaching = true`, listener gets called right away with last event.
  package func attach(_ listener: @escaping Listener) -> ObservationToken {
    defer {
      if emitsLastEventWhenAttaching {
        listener(lastEvent)
      }
    }

    let token = ObservationToken()
    let key = ObjectIdentifier(token)

    token.onCancel = { [weak self] in
      self?.mutableState.withValue {
        $0.listeners.removeAll { $0.key == key }
      }
    }

    mutableState.withValue {
      $0.listeners.append((key, listener))
    }

    return token
  }

  /// Trigger a new event on all attached listeners, or a specific listener owned by the `token` provided.
  package func emit(_ event: Event, to token: ObservationToken? = nil) {
    let listeners = mutableState.withValue {
      $0.lastEvent = event
      return $0.listeners
    }

    if let token {
      listeners.first { $0.key == ObjectIdentifier(token) }?.listener(event)
    } else {
      for (_, listener) in listeners {
        listener(event)
      }
    }
  }

  /// Returns a new ``AsyncStream`` for observing events emitted by this emitter.
  package func stream() -> AsyncStream<Event> {
    AsyncStream { continuation in
      let token = attach { status in
        continuation.yield(status)
      }

      continuation.onTermination = { _ in
        token.cancel()
      }
    }
  }
}
