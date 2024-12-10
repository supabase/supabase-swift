import ConcurrencyExtras
import Foundation
import Helpers

struct AuthStateChangeEventEmitter {
  var emitter = EventEmitter<(AuthChangeEvent, Session?)?>(
    initialEvent: nil,
    emitsLastEventWhenAttaching: false
  )
  var logger: (any SupabaseLogger)?

  func attach(_ listener: @escaping AuthStateChangeListener) -> ObservationToken {
    emitter.attach { event in
      guard let event else { return }
      listener(event.0, event.1)

      logger?.verbose("Auth state changed: \(event)")
    }
  }

  func emit(_ event: AuthChangeEvent, session: Session?, token: ObservationToken? = nil) {
    NotificationCenter.default.post(
      name: AuthClient.didChangeAuthStateNotification,
      object: nil,
      userInfo: [
        AuthClient.authChangeEventInfoKey: event,
        AuthClient.authChangeSessionInfoKey: session as Any,
      ]
    )

    emitter.emit((event, session), to: token)
  }
}
