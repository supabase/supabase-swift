//
//  EventEmitter.swift
//
//
//  Created by Guilherme Souza on 08/03/24.
//

import ConcurrencyExtras
import Foundation

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
}

extension ObservationToken {
  public func store(in collection: inout some RangeReplaceableCollection<ObservationToken>) {
    collection.append(self)
  }

  public func store(in set: inout Set<ObservationToken>) {
    set.insert(self)
  }
}

package final class EventEmitter<Event: Sendable>: Sendable {
  public typealias Listener = @Sendable (Event) -> Void

  private let listeners = LockIsolated<[(key: ObjectIdentifier, listener: Listener)]>([])
  private let _lastEvent: LockIsolated<Event>
  package var lastEvent: Event { _lastEvent.value }

  let emitsLastEventWhenAttaching: Bool

  package init(
    initialEvent event: Event,
    emitsLastEventWhenAttaching: Bool = true
  ) {
    _lastEvent = LockIsolated(event)
    self.emitsLastEventWhenAttaching = emitsLastEventWhenAttaching
  }

  package func attach(_ listener: @escaping Listener) -> ObservationToken {
    defer {
      if emitsLastEventWhenAttaching {
        listener(lastEvent)
      }
    }

    let token = ObservationToken()
    let key = ObjectIdentifier(token)

    token.onCancel = { [weak self] in
      self?.listeners.withValue {
        $0.removeAll { $0.key == key }
      }
    }

    listeners.withValue {
      $0.append((key, listener))
    }

    return token
  }

  package func emit(_ event: Event, to token: ObservationToken? = nil) {
    _lastEvent.setValue(event)
    let listeners = listeners.value

    if let token {
      listeners.first { $0.key == ObjectIdentifier(token) }?.listener(event)
    } else {
      for (_, listener) in listeners {
        listener(event)
      }
    }
  }

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
