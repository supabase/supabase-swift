//
//  PresenceHandle.swift
//  _Realtime
//
//  Created by Guilherme Souza on 24/04/25.
//

import Foundation
import IssueReporting

public final class PresenceHandle: Sendable {
  private let _cancel: @Sendable () async throws(RealtimeError) -> Void
  private let isCancelled = _Atomic(false)

  init(cancel: @escaping @Sendable () async throws(RealtimeError) -> Void) {
    self._cancel = cancel
  }

  deinit {
    if !isCancelled.value {
      reportIssue(
        "PresenceHandle deallocated without calling cancel() — presence was not untracked."
      )
    }
  }

  public func cancel() async throws(RealtimeError) {
    guard !isCancelled.exchange(true) else { return }
    try await _cancel()
  }
}

final class _Atomic<T: Sendable>: @unchecked Sendable {
  private var _value: T
  private let lock = NSLock()
  init(_ value: T) { _value = value }
  var value: T { lock.withLock { _value } }
  @discardableResult func exchange(_ newValue: T) -> T {
    lock.withLock { let old = _value; _value = newValue; return old }
  }
}
