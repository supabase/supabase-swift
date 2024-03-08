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
public protocol AuthStateChangeListenerRegistration: Sendable, AnyObject {
  /// Removes the listener. After the initial call, subsequent calls have no effect.
  func remove()
}

final class AuthStateChangeListenerHandle: AuthStateChangeListenerRegistration {
  let _onRemove = LockIsolated((@Sendable () -> Void)?.none)

  public func remove() {
    _onRemove.withValue {
      if $0 == nil {
        return
      }

      $0?()
      $0 = nil
    }
  }

  deinit {
    remove()
  }
}

public typealias AuthStateChangeListener = @Sendable (
  _ event: AuthChangeEvent,
  _ session: Session?
) -> Void
