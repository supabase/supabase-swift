//
//  AuthStateChangeListener.swift
//
//
//  Created by Guilherme Souza on 17/02/24.
//

import ConcurrencyExtras
import Foundation
import Helpers

/// A listener that can be removed by calling ``AuthStateChangeListenerRegistration/remove()``.
///
/// - Note: Listener is automatically removed on deinit.
public protocol AuthStateChangeListenerRegistration: Sendable {
  /// Removes the listener. After the initial call, subsequent calls have no effect.
  func remove()
}

extension ObservationToken: AuthStateChangeListenerRegistration {
  public func remove() {
    cancel()
  }
}

public typealias AuthStateChangeListener = @Sendable (
  _ event: AuthChangeEvent,
  _ session: Session?
) -> Void
