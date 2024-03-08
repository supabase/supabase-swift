import ConcurrencyExtras
import Foundation

protocol EventEmitter: Sendable {
  func attachListener(
    _ listener: @escaping AuthStateChangeListener
  ) -> AuthStateChangeListenerHandle

  func emit(
    _ event: AuthChangeEvent,
    session: Session?,
    handle: AuthStateChangeListenerHandle?
  )
}

extension EventEmitter {
  func emit(
    _ event: AuthChangeEvent,
    session: Session?
  ) {
    emit(event, session: session, handle: nil)
  }
}

final class DefaultEventEmitter: EventEmitter {
  static let shared = DefaultEventEmitter()

  private init() {}

  let listeners = LockIsolated<[ObjectIdentifier: AuthStateChangeListener]>([:])

  func attachListener(
    _ listener: @escaping AuthStateChangeListener
  ) -> AuthStateChangeListenerHandle {
    let handle = AuthStateChangeListenerHandle()
    let key = ObjectIdentifier(handle)

    handle._onRemove.setValue { [weak self] in
      self?.listeners.withValue {
        $0[key] = nil
      }
    }

    listeners.withValue {
      $0[key] = listener
    }

    return handle
  }

  func emit(
    _ event: AuthChangeEvent,
    session: Session?,
    handle: AuthStateChangeListenerHandle? = nil
  ) {
    NotificationCenter.default.post(
      name: AuthClient.didChangeAuthStateNotification,
      object: nil,
      userInfo: [
        AuthClient.authChangeEventInfoKey: event,
        AuthClient.authChangeSessionInfoKey: session as Any,
      ]
    )

    let listeners = listeners.value

    if let handle {
      listeners[ObjectIdentifier(handle)]?(event, session)
    } else {
      for listener in listeners.values {
        listener(event, session)
      }
    }
  }
}
