//
//  BackoffPolicy.swift
//  Helpers
//
//  Created by Guilherme Souza on 06/10/26.
//

/// How long to wait before the n-th retry: HTTP retries, Realtime connects and rejoins.
package struct BackoffPolicy: Sendable, Hashable {
  private enum Strategy: Hashable {
    case fullJitter(base: Duration, cap: Duration)
    case equalJitter(base: Duration, cap: Duration)
    case steps([Duration])
  }

  private let strategy: Strategy

  /// A random wait in `0...min(cap, base · 2^(attempt-1))`. Spreads reconnecting clients out
  /// after an outage better than equal jitter does.
  package static func fullJitter(base: Duration, cap: Duration) -> BackoffPolicy {
    BackoffPolicy(strategy: .fullJitter(base: base, cap: cap))
  }

  /// A random wait in `ceiling/2...ceiling`, where `ceiling = min(cap, base · 2^(attempt-1))`.
  /// Use it for a loop that only a time budget bounds: the floor keeps the waits growing, so the
  /// loop cannot send a burst of retries to a server that is already failing.
  package static func equalJitter(base: Duration, cap: Duration) -> BackoffPolicy {
    BackoffPolicy(strategy: .equalJitter(base: base, cap: cap))
  }

  /// Fixed waits, one per attempt; later attempts reuse the last one. Empty means no wait.
  package static func steps(_ steps: [Duration]) -> BackoffPolicy {
    BackoffPolicy(strategy: .steps(steps))
  }

  /// The wait before `attempt` (1-based; values below 1 count as 1).
  package func delay(
    forAttempt attempt: Int,
    random: (ClosedRange<Double>) -> Double = { Double.random(in: $0) }
  ) -> Duration {
    let attempt = max(attempt, 1)
    switch strategy {
    case .steps(let steps):
      guard let last = steps.last else { return .zero }
      return attempt <= steps.count ? steps[attempt - 1] : last
    case .fullJitter(let base, let cap):
      return Self.ceiling(attempt: attempt, base: base, cap: cap) * random(0...1)
    case .equalJitter(let base, let cap):
      let half = Self.ceiling(attempt: attempt, base: base, cap: cap) / 2
      return half + half * random(0...1)
    }
  }

  /// `min(cap, base · 2^(attempt-1))`, without overflow for a large `base` or `attempt`.
  private static func ceiling(attempt: Int, base: Duration, cap: Duration) -> Duration {
    let exponent = min(attempt - 1, 30)
    return base > cap / (1 << exponent) ? cap : base * (1 << exponent)
  }
}
