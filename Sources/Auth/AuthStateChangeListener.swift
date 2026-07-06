//
//  AuthStateChangeListener.swift
//
//
//  Created by Guilherme Souza on 17/02/24.
//

import ConcurrencyExtras
import Foundation

/// A listener that can be removed by calling ``AuthStateChangeListenerRegistration/remove()``.
///
/// - Note: Listener is automatically removed on deinit.
public protocol AuthStateChangeListenerRegistration: Sendable {
  /// Removes the listener. After the initial call, subsequent calls have no effect.
  func remove()
}

extension ObservationToken: AuthStateChangeListenerRegistration {}

/// A closure called whenever the authentication state changes.
///
/// - Parameters:
///   - event: The ``AuthChangeEvent`` that triggered this invocation.
///   - session: The current ``Session``, or `nil` when the user has signed out.
public typealias AuthStateChangeListener =
  @Sendable (
    _ event: AuthChangeEvent,
    _ session: Session?
  ) -> Void
