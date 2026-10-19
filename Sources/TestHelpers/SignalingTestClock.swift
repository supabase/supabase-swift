//
//  SignalingTestClock.swift
//  TestHelpers
//

package import Clocks
import Foundation

/// A `TestClock` whose `advance` waits for the sleep it is meant to fire.
///
/// swift-clocks' `TestClock.advance` fires the sleeps already registered and then moves `now`
/// on. A subject that schedules its sleep a few actor hops after the event a test observed (a
/// retry sleep after a failed connect, a backoff after a dropped socket) can register it after
/// `advance` has returned; the deadline is then in the past and never fires, and the test hangs.
///
/// This clock records every pending deadline itself. Before each step, `advance` waits up to
/// `grace` of real time for a sleep that the step would fire, then fires due sleeps in deadline
/// order and repeats, so chained sleeps (timeout, then retry) are honoured in one call. When no
/// sleep becomes due within the grace, it moves `now` to the target like `TestClock` does.
package final class SignalingTestClock: Clock, @unchecked Sendable {
  package typealias Instant = TestClock<Duration>.Instant

  private let inner = TestClock<Duration>()
  private let lock = NSLock()
  private var pending: [UUID: Instant] = [:]

  package init() {}

  package var now: Instant { inner.now }
  package var minimumResolution: Duration { inner.minimumResolution }

  package func sleep(until deadline: Instant, tolerance: Duration? = nil) async throws {
    let id = UUID()
    lock.withLock { pending[id] = deadline }
    defer { lock.withLock { pending[id] = nil } }
    try await inner.sleep(until: deadline, tolerance: tolerance)
  }

  /// Advances `now` by `duration`, firing every sleep that becomes due on the way.
  ///
  /// - Parameter grace: Real time to wait, before each step, for the subject to schedule a
  ///   sleep that the step would fire.
  // ponytail: real-time grace, not a registration signal; make `sleep` signal registration and
  // have tests advance per expected sleep if this is ever too slow or still races under load.
  package func advance(by duration: Duration, grace: Duration = .seconds(1)) async {
    let target = now.advanced(by: duration)
    while let next = await nextDeadline(upTo: target, grace: grace) {
      lock.withLock { pending = pending.filter { $0.value > next } }
      await inner.advance(to: next)
    }
    await inner.advance(to: target)
  }

  private func nextDeadline(upTo target: Instant, grace: Duration) async -> Instant? {
    let giveUp = ContinuousClock.now.advanced(by: grace)
    repeat {
      if let next = lock.withLock({ pending.values.filter { $0 <= target }.min() }) {
        return next
      }
      await Task.yield()
    } while ContinuousClock.now < giveUp
    return nil
  }
}
