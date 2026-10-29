//
//  BackoffPolicy.swift
//  Realtime
//
//  Created by Guilherme Souza on 06/10/26.
//

/// How long the client waits before the next attempt to reconnect.
///
/// Set it on ``RealtimeClientOptions/reconnectBackoff``. Attempts start at 1 and never stop while
/// the client wants a connection; the count starts again after a successful connect. A negative
/// wait counts as zero.
///
/// ```swift
/// var options = RealtimeClientOptions()
/// options.reconnectBackoff = .steps([.seconds(1), .seconds(5), .seconds(15)])
/// ```
///
/// ## Topics
/// ### Strategies
/// - ``fullJitter(base:cap:)``
/// - ``steps(_:)``
/// - ``custom(_:)``
/// ### Reading a Wait
/// - ``delay(forAttempt:)``
public struct BackoffPolicy: Sendable {
  private enum Strategy: Sendable {
    case fullJitter(base: Duration, cap: Duration)
    case steps([Duration])
    case custom(@Sendable (Int) -> Duration)
  }

  private let strategy: Strategy

  /// A random wait in `0...min(cap, base · 2^(attempt-1))`.
  ///
  /// Spreads reconnecting clients out after an outage better than a fixed or an equal-jitter wait
  /// does. This is the default, with a 1 s base and a 30 s cap.
  ///
  /// - Parameters:
  ///   - base: The upper bound of the first wait. It doubles on every later attempt.
  ///   - cap: The largest upper bound.
  public static func fullJitter(base: Duration, cap: Duration) -> BackoffPolicy {
    BackoffPolicy(strategy: .fullJitter(base: base, cap: cap))
  }

  /// Fixed waits, one per attempt. Later attempts reuse the last one. An empty list means no
  /// wait.
  ///
  /// - Parameter steps: The wait before attempt 1, attempt 2, and so on.
  public static func steps(_ steps: [Duration]) -> BackoffPolicy {
    BackoffPolicy(strategy: .steps(steps))
  }

  /// A wait that `delay` computes from the attempt number.
  ///
  /// ```swift
  /// options.reconnectBackoff = .custom { attempt in .seconds(min(attempt * 2, 20)) }
  /// ```
  ///
  /// - Parameter delay: Returns the wait before the given attempt. Attempts start at 1.
  public static func custom(_ delay: @escaping @Sendable (_ attempt: Int) -> Duration)
    -> BackoffPolicy
  {
    BackoffPolicy(strategy: .custom(delay))
  }

  /// The wait before `attempt`. Attempts start at 1; lower values count as 1.
  public func delay(forAttempt attempt: Int) -> Duration {
    delay(forAttempt: attempt, random: { Double.random(in: $0) })
  }

  /// The wait before `attempt`, with the jitter drawn from `random`. Tests pin it.
  package func delay(
    forAttempt attempt: Int,
    random: (ClosedRange<Double>) -> Double
  ) -> Duration {
    let attempt = max(attempt, 1)
    let delay: Duration
    switch strategy {
    case .steps(let steps):
      guard let last = steps.last else { return .zero }
      delay = attempt <= steps.count ? steps[attempt - 1] : last
    case .fullJitter(let base, let cap):
      let base = max(base, .zero)
      let cap = max(cap, .zero)
      let exponent = min(attempt - 1, 30)
      let ceiling = base > cap / (1 << exponent) ? cap : base * (1 << exponent)
      delay = ceiling * random(0...1)
    case .custom(let compute):
      delay = compute(attempt)
    }
    return max(delay, .zero)
  }
}
