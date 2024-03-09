//
//  MockEventEmitter.swift
//
//
//  Created by Guilherme Souza on 15/02/24.
//

@testable import Auth
import ConcurrencyExtras
import Foundation
import _Helpers

final class MockEventEmitter: EventEmitter {
  private let emitter = DefaultEventEmitter.shared

  func attachListener(_ listener: @escaping AuthStateChangeListener)
    -> ObservationToken
  {
    emitter.attachListener(listener)
  }

  private let _emitReceivedParams: LockIsolated<[(AuthChangeEvent, Session?)]> = .init([])
  var emitReceivedParams: [(AuthChangeEvent, Session?)] {
    _emitReceivedParams.value
  }

  func emit(
    _ event: AuthChangeEvent,
    session: Session?,
    token: ObservationToken? = nil
  ) {
    _emitReceivedParams.withValue {
      $0.append((event, session))
    }

    emitter.emit(event, session: session, token: token)
  }
}
