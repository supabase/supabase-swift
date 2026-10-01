//
//  RetryPolicy.swift
//  Helpers
//
//  Created by Guilherme Souza on 14/09/26.
//

package import Foundation
package import HTTPTypes

/// How a client retries a request that failed transiently.
///
/// One policy drives every module that retries (Auth, PostgREST, and the delay math of
/// Realtime's reconnect). A request is retried when its method is in ``retryableMethods`` and
/// the attempt either failed with a transient `URLError` or returned a status in
/// ``retryableStatuses``. The wait between attempts is capped exponential backoff with equal
/// jitter — `random(cap/2...cap)` where `cap = min(maxDelay, baseDelay · 2^(n-1))` for the n-th
/// retry — unless the response carried a `Retry-After` header, which is honoured up to
/// ``maxDelay``.
///
/// ponytail: `package` on purpose. Storage and Functions do not retry yet; which of their
/// requests are safe to replay is a separate decision, and this becomes public with it.
package struct RetryPolicy: Sendable, Hashable {
  /// Total attempts, including the first. `1` disables retries.
  package var maxAttempts: Int

  /// The cap for the first retry's wait; doubles on every further retry.
  package var baseDelay: Duration

  /// The longest wait between two attempts, jittered or `Retry-After`.
  package var maxDelay: Duration

  /// Response statuses worth retrying. Includes Cloudflare's 520–524 and 530, which front
  /// every Supabase project and report transient edge failures.
  package var retryableStatuses: Set<Int>

  /// Methods safe to replay. Add a method here only when every request that uses it is
  /// idempotent on the server.
  package var retryableMethods: Set<HTTPTypes.HTTPRequest.Method>

  /// Creates a policy. Every parameter defaults to the ``default`` policy's value.
  package init(
    maxAttempts: Int = 3,
    baseDelay: Duration = .milliseconds(500),
    maxDelay: Duration = .seconds(20),
    retryableStatuses: Set<Int> = [408, 429, 500, 502, 503, 504, 520, 521, 522, 523, 524, 530],
    retryableMethods: Set<HTTPTypes.HTTPRequest.Method> = [.get, .head, .options]
  ) {
    self.maxAttempts = maxAttempts
    self.baseDelay = baseDelay
    self.maxDelay = maxDelay
    self.retryableStatuses = retryableStatuses
    self.retryableMethods = retryableMethods
  }

  /// Three attempts, 500 ms base, 20 s cap, GET/HEAD/OPTIONS only.
  package static let `default` = RetryPolicy()

  /// A single attempt: the first failure is the final answer.
  package static let disabled = RetryPolicy(maxAttempts: 1)
}

extension RetryPolicy {
  /// Equal-jitter backoff for the `retry`-th retry (1-based): a random duration in
  /// `cap/2...cap`, where `cap = min(maxDelay, baseDelay · 2^(retry-1))`.
  package func backoffDelay(retry: Int) -> Duration {
    // Compare before multiplying: `baseDelay * (1 << exponent)` would overflow `Duration` for a
    // huge base, and the exponent is capped so `1 << exponent` itself cannot overflow.
    let exponent = min(max(retry - 1, 0), 30)
    let cap = baseDelay > maxDelay / (1 << exponent) ? maxDelay : baseDelay * (1 << exponent)
    let half = cap / 2
    return half + half * Double.random(in: 0...1)
  }

  /// The wait before the `retry`-th retry: `Retry-After` when present and parseable, capped at
  /// ``maxDelay``; otherwise ``backoffDelay(retry:)``.
  package func delay(retry: Int, retryAfter: String?, now: Date = Date()) -> Duration {
    if let retryAfter, let delay = Self.retryAfterDelay(retryAfter, now: now) {
      return min(delay, maxDelay)
    }
    return backoffDelay(retry: retry)
  }

  /// Parses a `Retry-After` value (RFC 9110 §10.2.3): non-negative delta-seconds or an
  /// IMF-fixdate in the future. Anything else is `nil`, so the jittered backoff applies — a
  /// date that has already passed carries no timing information, and a zero wait would make
  /// every client that saw it replay at the same instant.
  package static func retryAfterDelay(_ value: String, now: Date) -> Duration? {
    let value = value.trimmingCharacters(in: .whitespaces)
    if let seconds = Int(value) {
      return seconds >= 0 ? .seconds(seconds) : nil
    }
    // ponytail: IMF-fixdate only; the obsolete RFC 850 and asctime forms fall back to backoff.
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
    guard let date = formatter.date(from: value), date > now else { return nil }
    return .seconds(date.timeIntervalSince(now))
  }
}
