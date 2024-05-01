import _Helpers
import ConcurrencyExtras
import Foundation

struct AuthStateChangeEventEmitter {
  static let shared = AuthStateChangeEventEmitter(emitter: .init(initialEvent: nil, emitsLastEventWhenAttaching: false))

  let emitter: EventEmitter<(AuthChangeEvent, Session?)?>

  func attach(_ listener: @escaping AuthStateChangeListener) -> ObservationToken {
    emitter.attach { event in
      guard let event else { return }
      listener(event.0, event.1)
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
