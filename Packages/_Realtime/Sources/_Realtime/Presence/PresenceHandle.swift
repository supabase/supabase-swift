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
