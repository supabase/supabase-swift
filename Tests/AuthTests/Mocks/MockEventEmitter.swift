//
//  MockEventEmitter.swift
//
//
//  Created by Guilherme Souza on 15/02/24.
//

@testable import Auth
import ConcurrencyExtras
import Foundation

final class MockEventEmitter: EventEmitter {
  let emitReceivedParams: LockIsolated<[(AuthChangeEvent, Session?)]> = .init([])

  override func emit(
    _ event: AuthChangeEvent,
    session: Session?,
    handle: AuthStateChangeListenerHandle? = nil
  ) {
    emitReceivedParams.withValue {
      $0.append((event, session))
    }
    super.emit(event, session: session, handle: handle)
  }
}
