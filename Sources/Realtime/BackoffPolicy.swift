//
//  BackoffPolicy.swift
//  Realtime
//
//  Created by Guilherme Souza on 06/10/26.
//

/// How long to wait before the n-th reconnect attempt.
struct BackoffPolicy: Sendable, Hashable {
  let base: Duration
  let cap: Duration

  /// A random wait in `0...min(cap, base · 2^(attempt-1))`. Spreads reconnecting clients out
  /// after an outage better than equal jitter does.
  static func fullJitter(base: Duration, cap: Duration) -> BackoffPolicy {
    BackoffPolicy(base: base, cap: cap)
  }

  /// The wait before `attempt` (1-based; values below 1 count as 1).
  func delay(
    forAttempt attempt: Int,
    random: (ClosedRange<Double>) -> Double = { Double.random(in: $0) }
  ) -> Duration {
    let exponent = min(max(attempt, 1) - 1, 30)
    let ceiling = base > cap / (1 << exponent) ? cap : base * (1 << exponent)
    return ceiling * random(0...1)
  }
}
