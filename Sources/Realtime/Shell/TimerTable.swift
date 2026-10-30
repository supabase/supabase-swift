//
//  TimerTable.swift
//  Realtime
//

import Foundation

/// The timers the core started with ``RealtimeCore/Effect/schedule(_:after:)``. The actor owns the
/// table, so it needs no lock.
///
/// Every timer has a token. A timer that was replaced or cancelled can still deliver a `fire` that
/// was already on its way, so the actor checks ``isCurrent(_:token:)`` before it acts on one.
struct TimerTable {
  private struct Entry {
    let token: UInt64
    let task: Task<Void, Never>
  }

  private var lastToken: UInt64 = 0
  private var entries: [TimerID: Entry] = [:]

  /// Starts a timer for `id` that calls `fire` with the id and its token after `delay`. A timer
  /// already scheduled for `id` is cancelled and replaced.
  mutating func schedule(
    _ id: TimerID,
    after delay: Duration,
    clock: any Clock<Duration>,
    fire: @escaping @Sendable (TimerID, UInt64) async -> Void
  ) {
    entries[id]?.task.cancel()
    lastToken += 1
    let token = lastToken
    let task = Task {
      do {
        try await clock.sleep(for: delay)
      } catch {
        return
      }
      guard !Task.isCancelled else { return }
      await fire(id, token)
    }
    entries[id] = Entry(token: token, task: task)
  }

  mutating func cancel(_ id: TimerID) {
    entries.removeValue(forKey: id)?.task.cancel()
  }

  /// Cancels every timer and leaves the table empty.
  mutating func cancelAll() {
    for entry in entries.values {
      entry.task.cancel()
    }
    entries.removeAll()
  }

  /// Whether `token` belongs to the timer now scheduled for `id`.
  func isCurrent(_ id: TimerID, token: UInt64) -> Bool {
    entries[id]?.token == token
  }
}
