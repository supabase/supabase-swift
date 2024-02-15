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
  let emitedParams: LockIsolated<[(AuthChangeEvent, Session?, AuthStateChangeListenerHandle?)]> =
    .init([])

  override func emit(
    _ event: AuthChangeEvent,
    session: Session?,
    handle: AuthStateChangeListenerHandle? = nil
  ) {
    emitedParams.withValue {
      $0.append((event, session, handle))
    }
  }
}
