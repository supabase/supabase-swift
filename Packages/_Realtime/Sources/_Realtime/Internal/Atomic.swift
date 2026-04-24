//
//  Atomic.swift
//  _Realtime
//
//  Created by Guilherme Souza on 24/04/25.
//

import Foundation

final class _Atomic<T: Sendable>: @unchecked Sendable {
  private var _value: T
  private let lock = NSLock()
  init(_ value: T) { _value = value }
  var value: T { lock.withLock { _value } }
  @discardableResult func exchange(_ newValue: T) -> T {
    lock.withLock { let old = _value; _value = newValue; return old }
  }
}

/// Wraps a CheckedContinuation so that only the first resume call wins.
final class OnceResumingContinuation<T: Sendable>: @unchecked Sendable {
  private let inner: CheckedContinuation<T, any Error>
  private let claimed = _Atomic(false)

  init(_ continuation: CheckedContinuation<T, any Error>) {
    self.inner = continuation
  }

  func resume(returning value: T) {
    guard !claimed.exchange(true) else { return }
    inner.resume(returning: value)
  }

  func resume(throwing error: any Error) {
    guard !claimed.exchange(true) else { return }
    inner.resume(throwing: error)
  }
}
