import _Helpers
import ConcurrencyExtras
import Foundation

struct EventEmitter: Sendable {
  var attachListener: @Sendable (
    _ listener: @escaping AuthStateChangeListener
  ) -> ObservationToken

  var emit: @Sendable (
    _ event: AuthChangeEvent,
    _ session: Session?,
    _ token: ObservationToken?
  ) -> Void
}

extension EventEmitter {
  func emit(
    _ event: AuthChangeEvent,
    session: Session?
  ) {
    emit(event, session, nil)
  }
}

extension EventEmitter {
  static let live: EventEmitter = {
    let emitter = _Helpers.EventEmitter<(AuthChangeEvent, Session?)?>(
      initialEvent: nil,
      emitsLastEventWhenAttaching: false
    )

    return EventEmitter(
      attachListener: { listener in
        emitter.attach { event in
          guard let event else { return }
          listener(event.0, event.1)
        }
      },
      emit: { event, session, token in
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
    )
  }()
}
