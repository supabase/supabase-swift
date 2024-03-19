import ConcurrencyExtras
import Foundation
@_spi(Internal) import _Helpers

protocol EventEmitter: Sendable {
  func attachListener(
    _ listener: @escaping AuthStateChangeListener
  ) -> ObservationToken

  func emit(
    _ event: AuthChangeEvent,
    session: Session?,
    token: ObservationToken?
  )
}

extension EventEmitter {
  func emit(
    _ event: AuthChangeEvent,
    session: Session?
  ) {
    emit(event, session: session, token: nil)
  }
}

final class DefaultEventEmitter: EventEmitter {
  static let shared = DefaultEventEmitter()

  private init() {}

  let emitter = _Helpers.EventEmitter<(AuthChangeEvent, Session?)?>(
    initialEvent: nil,
    emitsLastEventWhenAttaching: false
  )

  func attachListener(
    _ listener: @escaping AuthStateChangeListener
  ) -> ObservationToken {
    emitter.attach { event in
      guard let event else { return }
      listener(event.0, event.1)
    }
  }

  func emit(
    _ event: AuthChangeEvent,
    session: Session?,
    token: ObservationToken? = nil
  ) {
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
