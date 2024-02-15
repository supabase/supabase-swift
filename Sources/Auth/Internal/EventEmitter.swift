import ConcurrencyExtras
import Foundation

class EventEmitter: @unchecked Sendable {
  let listeners = LockIsolated<[ObjectIdentifier: AuthStateChangeListener]>([:])

  func attachListener(_ listener: @escaping AuthStateChangeListener)
    -> AuthStateChangeListenerHandle
  {
    let handle = AuthStateChangeListenerHandle()
    let key = ObjectIdentifier(handle)

    handle.onCancel = { [weak self] in
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
