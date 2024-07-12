//
//  EventEmitter.swift
//
//
//  Created by Guilherme Souza on 08/03/24.
//

import ConcurrencyExtras
import Foundation

public final class ObservationToken: Sendable, Hashable {
  let _onCancel = LockIsolated((@Sendable () -> Void)?.none)

  package init(_ onCancel: (@Sendable () -> Void)? = nil) {
    _onCancel.setValue(onCancel)
  }

  @available(*, deprecated, renamed: "cancel")
  public func remove() {
    cancel()
  }

  public func cancel() {
    _onCancel.withValue {
      if $0 == nil {
        return
      }

      $0?()
      $0 = nil
    }
  }

  deinit {
    cancel()
  }

  public static func == (lhs: ObservationToken, rhs: ObservationToken) -> Bool {
    ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(ObjectIdentifier(self))
  }
}

extension ObservationToken {
  public func store(in set: inout Set<ObservationToken>) {
    set.insert(self)
  }
}

package final class EventEmitter<Event: Sendable>: Sendable {
  public typealias Listener = @Sendable (Event) -> Void

  private let listeners = LockIsolated<[ObjectIdentifier: Listener]>([:])
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

    token._onCancel.setValue { [weak self] in
      self?.listeners.withValue {
        $0[key] = nil
      }
    }

    listeners.withValue {
      $0[key] = listener
    }

    return token
  }

  package func emit(_ event: Event, to token: ObservationToken? = nil) {
    _lastEvent.setValue(event)
    let listeners = listeners.value

    if let token {
      listeners[ObjectIdentifier(token)]?(event)
    } else {
      for listener in listeners.values {
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
