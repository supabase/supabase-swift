//
//  RetryRequestInterceptor.swift
//
//
//  Created by Guilherme Souza on 23/04/24.
//

import Foundation
package import HTTPTypes

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// The one ``ClientMiddleware`` that retries failed requests, for every HTTP module.
///
/// Driven entirely by a ``RetryPolicy``: which methods and statuses are retryable, how many
/// attempts, and how long to wait (full-jitter backoff or `Retry-After`). Sends
/// `X-Retry-Count: n` on the n-th retry so a server can tell a replay from a first attempt.
///
/// A request whose body is ``HTTPBody/IterationBehavior/single`` is never retried — the bytes
/// are gone after the first send. Only a `URLError` counts as a transport failure; an error
/// thrown by user code propagates untouched. `CancellationError` (and `URLError.cancelled`) end
/// the loop at once, and a cancellation that lands during the backoff wait propagates as itself.
package struct RetryRequestInterceptor: ClientMiddleware {
  package let policy: RetryPolicy
  package let clock: any Clock<Duration>

  package init(policy: RetryPolicy, clock: any Clock<Duration> = ContinuousClock()) {
    self.policy = policy
    self.clock = clock
  }

  package func intercept(
    _ request: HTTPTypes.HTTPRequest,
    body: HTTPBody?,
    next:
      @Sendable (HTTPTypes.HTTPRequest, HTTPBody?) async throws -> (
        HTTPTypes.HTTPResponse, HTTPBody?
      )
  ) async throws -> (HTTPTypes.HTTPResponse, HTTPBody?) {
    // A one-shot body cannot be replayed, so the request is not retryable regardless of method.
    guard body?.iterationBehavior != .single else {
      return try await next(request, body)
    }

    var attempt = 1
    while true {
      var current = request
      if attempt > 1 {
        current.headerFields[.xRetryCount] = "\(attempt - 1)"
      }

      let result: Result<(HTTPTypes.HTTPResponse, HTTPBody?), any Error>
      do {
        result = .success(try await next(current, body))
      } catch {
        result = .failure(error)
      }

      guard attempt < policy.maxAttempts, shouldRetry(request, result: result) else {
        return try result.get()
      }

      // This attempt's body is about to be discarded, so drain it to termination — a streamed
      // body holds its producer (a URLSession task) open until its stream finishes. Exceeding
      // the cap throws, which drops the iterator and terminates the stream just the same.
      if let responseBody = result.value?.1 {
        _ = try? await Data(collecting: responseBody, upTo: 1 << 20)
      }

      let retryAfter = result.value?.0.headerFields[.retryAfter]
      try await clock.sleep(for: policy.delay(retry: attempt, retryAfter: retryAfter))
      attempt += 1
    }
  }

  private func shouldRetry(
    _ request: HTTPTypes.HTTPRequest,
    result: Result<(HTTPTypes.HTTPResponse, HTTPBody?), any Error>
  ) -> Bool {
    guard
      policy.retryableMethods.contains(request.method)
        || request.headerFields[.idempotencyKey] != nil
    else { return false }

    switch result {
    case .success(let (head, _)):
      return policy.retryableStatuses.contains(head.status.code)
    case .failure(let error as URLError):
      // ponytail: every URLError but a cancellation counts as transient. A deterministic one
      // (bad URL, untrusted certificate) costs at most two short extra attempts; a curated
      // code list is the upgrade if that ever matters.
      return error.code != .cancelled
    case .failure:
      // `CancellationError`, and anything thrown by user code (a custom transport or
      // middleware, an `accessToken` closure) — those propagate as themselves.
      return false
    }
  }
}
