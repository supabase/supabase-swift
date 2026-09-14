//
//  RetryPolicy.swift
//  Helpers
//
//  Created by Guilherme Souza on 14/09/26.
//

package import Foundation
public import HTTPTypes

/// How a client retries a request that failed transiently.
///
/// One policy drives every HTTP module (Auth, PostgREST, Storage, Functions). A request is
/// retried when its method is in ``retryableMethods`` (or it carries an `Idempotency-Key`
/// header), and the attempt either threw a transport error or returned a status in
/// ``retryableStatuses``. The wait between attempts is capped exponential backoff with full
/// jitter — `random(0...min(maxDelay, baseDelay · 2^(n-1)))` for the n-th retry — unless the
/// response carried a `Retry-After` header, which is honoured up to ``maxDelay``.
///
/// ```swift
/// // Never retry.
/// PostgrestClient.Configuration(url: url, retryPolicy: .disabled)
///
/// // Retry harder, but only reads.
/// var policy = RetryPolicy.default
/// policy.maxAttempts = 5
/// policy.retryableMethods = [.get, .head]
/// ```
public struct RetryPolicy: Sendable, Hashable {
  /// Total attempts, including the first. `1` disables retries.
  public var maxAttempts: Int

  /// The cap for the first retry's wait; doubles on every further retry.
  public var baseDelay: Duration

  /// The longest wait between two attempts, jittered or `Retry-After`.
  public var maxDelay: Duration

  /// Response statuses worth retrying. Includes Cloudflare's 520–524 and 530, which front
  /// every Supabase project and report transient edge failures.
  public var retryableStatuses: Set<Int>

  /// Methods safe to replay. A request outside this set is still retried when it carries an
  /// `Idempotency-Key` header.
  public var retryableMethods: Set<HTTPTypes.HTTPRequest.Method>

  /// Creates a policy. Every parameter defaults to the ``default`` policy's value.
  public init(
    maxAttempts: Int = 3,
    baseDelay: Duration = .milliseconds(500),
    maxDelay: Duration = .seconds(20),
    retryableStatuses: Set<Int> = [408, 429, 500, 502, 503, 504, 520, 521, 522, 523, 524, 530],
    retryableMethods: Set<HTTPTypes.HTTPRequest.Method> = [.get, .head, .options, .put, .delete]
  ) {
    self.maxAttempts = maxAttempts
    self.baseDelay = baseDelay
    self.maxDelay = maxDelay
    self.retryableStatuses = retryableStatuses
    self.retryableMethods = retryableMethods
  }

  /// Three attempts, 500 ms base, 20 s cap, idempotent methods only.
  public static let `default` = RetryPolicy()

  /// A single attempt: the first failure is the final answer.
  public static let disabled = RetryPolicy(maxAttempts: 1)
}

extension RetryPolicy {
  /// Full-jitter backoff for the `retry`-th retry (1-based): a random duration in
  /// `0...min(maxDelay, baseDelay · 2^(retry-1))`.
  package func backoffDelay(retry: Int) -> Duration {
    // Cap the exponent so `1 << exponent` cannot overflow on a runaway attempt counter — the
    // result is clamped to `maxDelay` right after anyway.
    let exponent = min(max(retry - 1, 0), 30)
    let cap = min(maxDelay, baseDelay * (1 << exponent))
    guard cap > .zero else { return .zero }
    return .seconds(Double.random(in: 0...cap.timeInterval))
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
  /// IMF-fixdate. A date in the past is `.zero`; anything else is `nil`.
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
    guard let date = formatter.date(from: value) else { return nil }
    return .seconds(max(0, date.timeIntervalSince(now)))
  }
}

extension Duration {
  fileprivate var timeInterval: TimeInterval {
    Double(components.seconds) + Double(components.attoseconds) / 1e18
  }
}
