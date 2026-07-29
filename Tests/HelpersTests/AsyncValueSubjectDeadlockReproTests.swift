//
//  AsyncValueSubjectDeadlockReproTests.swift
//  Supabase
//

import ConcurrencyExtras
import Testing

@testable import Helpers

@Suite
struct AsyncValueSubjectDeadlockReproTests {

  /// Mirrors the production deadlock from
  /// https://github.com/supabase/supabase-swift/issues/1154:
  /// `withTimeout`'s `group.cancelAll()` cancels a task consuming
  /// `subject.values` (task-group cancel path) at the same moment another
  /// thread is inside `subject.yield()` resuming that same task's
  /// continuation (yield path). Lock order is inverted between the two
  /// paths, so this can deadlock.
  @Test(.timeLimit(.minutes(1)))
  func stressWithTimeoutCancelRacingYield() async throws {
    let subject = AsyncValueSubject<Int>(0)

    let yielder = Task.detached {
      var i = 0
      while !Task.isCancelled {
        subject.yield(i)
        i += 1
      }
    }

    for _ in 0..<3000 {
      _ = try? await withTimeout(interval: 0.0001) {
        for await _ in subject.values {}
      }
    }

    yielder.cancel()
    _ = await yielder.value
  }
}
