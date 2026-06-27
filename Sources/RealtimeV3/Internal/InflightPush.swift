//
//  InflightPush.swift
//  RealtimeV3
//
//  Created by Guilherme Souza on 27/06/26.
//

import Clocks
import ConcurrencyExtras
import Foundation

/// Reply value for a Phoenix push.
typealias PushReply = (status: String, response: JSONValue)

/// Tracks in-flight pushes that are waiting for a `phx_reply` from the server.
///
/// Callers register a push via `awaitReply`, which suspends until the matching
/// reply arrives or the timeout fires. The frame router calls `resolve` when a
/// `phx_reply` frame arrives; `failAll` is called on disconnect to drain the
/// pending map immediately.
///
/// ## Design Notes
///
/// The pending-continuation map is stored in a `LockIsolated` dict rather than
/// plain actor state. This lets the `withCheckedThrowingContinuation` setup
/// closure (which is `nonisolated`) store the continuation atomically without
/// having to hop onto the actor, eliminating the registration race that would
/// exist if we used `Task { await self._register(...) }`.
///
/// Double-resume is prevented by removing the entry from the map at the moment
/// the continuation is resumed in all three paths (resolve, timeout, failAll).
actor InflightPushRegistry {
  private struct Entry: @unchecked Sendable {
    let continuation: CheckedContinuation<PushReply, any Error>
    let timeoutError: RealtimeError
  }

  /// Continuations stored under a lock so the nonisolated setup closure of
  /// `withCheckedThrowingContinuation` can write to the map synchronously.
  private let pendingLock = LockIsolated([String: Entry]())

  /// Number of pushes currently awaiting a reply. Used by tests to
  /// deterministically observe registration before advancing a test clock.
  var pendingCount: Int {
    pendingLock.withValue { $0.count }
  }

  /// Suspends until the `phx_reply` for `ref` arrives, or until `timeout` elapses
  /// on `clock`. On timeout, `timeoutError` is thrown.
  func awaitReply(
    ref: String,
    timeout: Duration,
    clock: any Clock<Duration>,
    timeoutError: RealtimeError
  ) async throws(RealtimeError) -> PushReply {
    do {
      return try await _awaitReply(
        ref: ref, timeout: timeout, clock: clock, timeoutError: timeoutError)
    } catch let error as RealtimeError {
      throw error
    } catch {
      throw .cancelled
    }
  }

  private func _awaitReply(
    ref: String,
    timeout: Duration,
    clock: any Clock<Duration>,
    timeoutError: RealtimeError
  ) async throws -> PushReply {
    // Spawn a timeout task before registering the continuation, so the timer
    // starts as close to the send moment as possible.
    let timeoutTask = Task { [pendingLock] in
      do {
        try await clock.sleep(for: timeout)
      } catch {
        // CancellationError: reply arrived first; nothing to do.
        return
      }
      // Timeout fired: remove and resume the continuation if it's still pending.
      pendingLock.withValue { dict in
        guard let entry = dict.removeValue(forKey: ref) else { return }
        entry.continuation.resume(throwing: entry.timeoutError)
      }
    }

    do {
      let result = try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<PushReply, any Error>) in
        // This closure runs synchronously before the outer function suspends.
        // LockIsolated.withValue is safe to call from nonisolated context.
        pendingLock.withValue { dict in
          if Task.isCancelled {
            continuation.resume(throwing: CancellationError())
          } else {
            dict[ref] = Entry(continuation: continuation, timeoutError: timeoutError)
          }
        }
      }
      timeoutTask.cancel()
      return result
    } catch {
      timeoutTask.cancel()
      throw error
    }
  }

  /// Called by the frame router when a `phx_reply` frame arrives.
  /// Resolving an unknown ref is a no-op (double-resolve guard).
  func resolve(ref: String, status: String, response: JSONValue) {
    pendingLock.withValue { dict in
      guard let entry = dict.removeValue(forKey: ref) else { return }
      entry.continuation.resume(returning: (status: status, response: response))
    }
  }

  /// Fails all outstanding pushes immediately with `error`.
  func failAll(_ error: RealtimeError) {
    let entries = pendingLock.withValue { dict -> [Entry] in
      let all = Array(dict.values)
      dict.removeAll()
      return all
    }
    for entry in entries {
      entry.continuation.resume(throwing: error)
    }
  }
}
