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
/// Driven by a ``RetryPolicy``: which methods and statuses are retryable, how many attempts, and
/// how long to wait (equal-jitter backoff or `Retry-After`). Sends `X-Retry-Count: n` on the
/// n-th retry so a server can tell a replay from a first attempt.
///
/// Runs outermost — ahead of the caller's middlewares and the SDK's own — so every attempt
/// re-runs the whole chain and, in particular, resolves a fresh access token.
///
/// A request whose body is ``HTTPBody/IterationBehavior/single`` is never retried — the bytes
/// are gone after the first send. Only a `URLError` in ``retryableURLErrorCodes`` counts as a
/// transport failure; a deterministic one (bad URL, untrusted certificate) and any error thrown
/// by user code propagate untouched. A cancelled task ends the loop at once and always surfaces
/// as `CancellationError`, even when the transport reported it as `URLError.cancelled`.
package struct RetryRequestInterceptor: ClientMiddleware {
  /// The `URLError` codes that mean "try again", as opposed to a deterministic failure.
  static let retryableURLErrorCodes: Set<URLError.Code> = [
    .backgroundSessionInUseByAnotherProcess, .backgroundSessionWasDisconnected,
    .badServerResponse, .callIsActive, .cannotConnectToHost, .cannotFindHost,
    .cannotLoadFromNetwork, .dataNotAllowed, .dnsLookupFailed,
    .downloadDecodingFailedMidStream, .downloadDecodingFailedToComplete,
    .internationalRoamingOff, .networkConnectionLost, .notConnectedToInternet,
    .secureConnectionFailed, .serverCertificateHasBadDate,
    .serverCertificateNotYetValid, .timedOut,
  ]

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
        // A cancellation mid-flight comes back from the transport as `URLError.cancelled`;
        // report it as what it is.
        try Task.checkCancellation()
        return try result.get()
      }

      // This attempt's body is about to be discarded. Drain it now so its producer (a URLSession
      // task) finishes deterministically instead of whenever ARC releases the body — which may
      // be after the backoff sleep. Exceeding the cap throws, which drops the iterator and
      // terminates the stream just the same.
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
    guard policy.retryableMethods.contains(request.method) else { return false }

    switch result {
    case .success(let (head, _)):
      return policy.retryableStatuses.contains(head.status.code)
    case .failure(let error as URLError):
      return Self.retryableURLErrorCodes.contains(error.code)
    case .failure:
      // `CancellationError`, and anything thrown by user code (a custom transport or
      // middleware, an `accessToken` closure) — those propagate as themselves.
      return false
    }
  }
}
