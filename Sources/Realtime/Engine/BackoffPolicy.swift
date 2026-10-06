//
//  BackoffPolicy.swift
//  Realtime
//
//  Created by Guilherme Souza on 06/10/26.
//

/// How long to wait before the n-th retry of a connect or a rejoin.
package struct BackoffPolicy: Sendable, Hashable {
  private enum Strategy: Hashable {
    case fullJitter(base: Duration, cap: Duration)
    case steps([Duration])
  }

  private let strategy: Strategy

  /// A random wait in `0...min(cap, base · 2^(attempt-1))`. Spreads reconnecting clients out
  /// after an outage better than equal jitter does.
  package static func fullJitter(base: Duration, cap: Duration) -> BackoffPolicy {
    BackoffPolicy(strategy: .fullJitter(base: base, cap: cap))
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
      // Compare before multiplying so a huge base cannot overflow `Duration`.
      let exponent = min(attempt - 1, 30)
      let ceiling = base > cap / (1 << exponent) ? cap : base * (1 << exponent)
      return ceiling * random(0...1)
    }
  }
}
