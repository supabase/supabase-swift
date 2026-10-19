//
//  StatusMirror.swift
//  Realtime
//
//  Created by Guilherme Souza on 19/10/26.
//

import ConcurrencyExtras
import Foundation

/// A lock-protected copy of an actor-isolated status, so `nonisolated` readers and
/// `AsyncStream` subscribers see the value without an `await`.
///
/// The owner writes it in the same synchronous stretch that mutates its isolated state, so the
/// mirror never lags behind the source of truth. The lock exists only because readers are not on
/// the owner's executor; it is the one lock in the module.
final class StatusMirror<Status: Sendable>: Sendable {
  private struct State {
    var status: Status
    var continuations: [UUID: AsyncStream<Status>.Continuation] = [:]
  }

  private let state: LockIsolated<State>

  init(_ status: Status) {
    state = LockIsolated(State(status: status))
  }

  var current: Status { state.value.status }

  /// Records `status` and yields it to every open stream.
  ///
  /// Continuations are snapshotted under the lock and resumed outside of it: resuming can take
  /// the runtime's task-status lock, and holding ours at the same time inverts the order
  /// cancellation takes (supabase-swift#1154).
  func update(_ status: Status) {
    let continuations = state.withValue { state in
      state.status = status
      return Array(state.continuations.values)
    }
    for continuation in continuations {
      continuation.yield(status)
    }
  }

  /// A stream of every update, starting with the current value when `replayingCurrent` is set.
  ///
  /// Unbounded: consumers wait for a specific value rather than sampling the latest, and
  /// transitions arrive back to back (`.disconnected` then `.connecting` on an auto-reconnect),
  /// so a bounded policy could evict the one being waited on.
  func stream(replayingCurrent: Bool = true) -> AsyncStream<Status> {
    let id = UUID()
    let (stream, continuation) = AsyncStream<Status>.makeStream(bufferingPolicy: .unbounded)
    let current = state.withValue { state in
      state.continuations[id] = continuation
      return state.status
    }
    continuation.onTermination = { [weak self] _ in
      self?.state.withValue { _ = $0.continuations.removeValue(forKey: id) }
    }
    if replayingCurrent {
      continuation.yield(current)
    }
    return stream
  }

  /// Ends every open stream. The owner calls this from `deinit`.
  func finish() {
    let continuations = state.withValue { state in
      defer { state.continuations.removeAll() }
      return Array(state.continuations.values)
    }
    for continuation in continuations {
      continuation.finish()
    }
  }
}
