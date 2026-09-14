//
//  RetryRequestInterceptor.swift
//
//
//  Created by Guilherme Souza on 23/04/24.
//

package import Foundation
package import HTTPTypes

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// A ``ClientMiddleware`` for retrying failed HTTP requests with exponential backoff.
///
/// The `RetryRequestInterceptor` actor intercepts HTTP requests and automatically retries them in case
/// of failure, with exponential backoff between retries. You can configure the retry behavior by specifying
/// the retry limit, exponential backoff base, scale, retryable HTTP methods, HTTP status codes, and URL error codes.
package actor RetryRequestInterceptor: ClientMiddleware {
  /// The default retry limit for the interceptor.
  package static let defaultRetryLimit = 2
  /// The default base value for exponential backoff.
  package static let defaultExponentialBackoffBase: UInt = 2
  /// The default scale factor for exponential backoff.
  package static let defaultExponentialBackoffScale: Double = 0.5

  /// The default set of retryable HTTP methods.
  package static let defaultRetryableHTTPMethods: Set<HTTPTypes.HTTPRequest.Method> = [
    .delete, .get, .head, .options, .put, .trace,
  ]

  /// The default set of retryable URL error codes.
  package static let defaultRetryableURLErrorCodes: Set<URLError.Code> = [
    .backgroundSessionInUseByAnotherProcess, .backgroundSessionWasDisconnected,
    .badServerResponse, .callIsActive, .cannotConnectToHost, .cannotFindHost,
    .cannotLoadFromNetwork, .dataNotAllowed, .dnsLookupFailed,
    .downloadDecodingFailedMidStream, .downloadDecodingFailedToComplete,
    .internationalRoamingOff, .networkConnectionLost, .notConnectedToInternet,
    .secureConnectionFailed, .serverCertificateHasBadDate,
    .serverCertificateNotYetValid, .timedOut,
  ]

  /// The default set of retryable HTTP status codes.
  ///
  /// Includes Cloudflare-specific error codes (520-524, 530) which represent transient
  /// infrastructure errors that should not cause session invalidation.
  package static let defaultRetryableHTTPStatusCodes: Set<Int> = [
    408, 500, 502, 503, 504,
    // Cloudflare-specific transient errors
    520, 521, 522, 523, 524, 530,
  ]

  /// The maximum number of retries.
  package let retryLimit: Int
  /// The base value for exponential backoff.
  package let exponentialBackoffBase: UInt
  /// The scale factor for exponential backoff.
  package let exponentialBackoffScale: Double
  /// The set of retryable HTTP methods.
  package let retryableHTTPMethods: Set<HTTPTypes.HTTPRequest.Method>
  /// The set of retryable HTTP status codes.
  package let retryableHTTPStatusCodes: Set<Int>
  /// The set of retryable URL error codes.
  package let retryableErrorCodes: Set<URLError.Code>
  /// The clock used to wait between retries.
  package let clock: any Clock<Duration>

  /// Creates a `RetryRequestInterceptor` instance.
  ///
  /// - Parameters:
  ///   - retryLimit: The maximum number of retries. Default is `2`.
  ///   - exponentialBackoffBase: The base value for exponential backoff. Default is `2`.
  ///   - exponentialBackoffScale: The scale factor for exponential backoff. Default is `0.5`.
  ///   - retryableHTTPMethods: The set of retryable HTTP methods. Default includes common methods.
  ///   - retryableHTTPStatusCodes: The set of retryable HTTP status codes. Default includes common status codes.
  ///   - retryableErrorCodes: The set of retryable URL error codes. Default includes common error codes.
  ///   - clock: The clock used to wait between retries. Default is `ContinuousClock()`.
  package init(
    retryLimit: Int = RetryRequestInterceptor.defaultRetryLimit,
    exponentialBackoffBase: UInt = RetryRequestInterceptor.defaultExponentialBackoffBase,
    exponentialBackoffScale: Double = RetryRequestInterceptor.defaultExponentialBackoffScale,
    retryableHTTPMethods: Set<HTTPTypes.HTTPRequest.Method> = RetryRequestInterceptor
      .defaultRetryableHTTPMethods,
    retryableHTTPStatusCodes: Set<Int> = RetryRequestInterceptor.defaultRetryableHTTPStatusCodes,
    retryableErrorCodes: Set<URLError.Code> = RetryRequestInterceptor.defaultRetryableURLErrorCodes,
    clock: any Clock<Duration> = ContinuousClock()
  ) {
    // A base below 2 makes each wait shorter than the last instead of longer. The value is fixed
    // at construction, so this is a programmer error, not a runtime condition.
    precondition(
      exponentialBackoffBase >= 2,
      "The `exponentialBackoffBase` must be a minimum of 2."
    )

    self.retryLimit = retryLimit
    self.exponentialBackoffBase = exponentialBackoffBase
    self.exponentialBackoffScale = exponentialBackoffScale
    self.retryableHTTPMethods = retryableHTTPMethods
    self.retryableHTTPStatusCodes = retryableHTTPStatusCodes
    self.retryableErrorCodes = retryableErrorCodes
    self.clock = clock
  }

  /// Intercepts an HTTP request and automatically retries it in case of failure.
  ///
  /// - Parameters:
  ///   - request: The original HTTP request to be intercepted and retried.
  ///   - body: The outgoing body, if any.
  ///   - next: A closure representing the rest of the chain.
  /// - Returns: The HTTP response obtained after retrying.
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
    return try await retry(request, body: body, retryCount: 1, next: next)
  }

  private func shouldRetry(
    request: HTTPTypes.HTTPRequest,
    result: Result<HTTPTypes.HTTPResponse, any Error>
  ) -> Bool {
    guard retryableHTTPMethods.contains(request.method) else { return false }

    if let head = result.value, retryableHTTPStatusCodes.contains(head.status.code) {
      return true
    }

    guard let errorCode = (result.error as? URLError)?.code else {
      return false
    }

    return retryableErrorCodes.contains(errorCode)
  }

  private func retry(
    _ request: HTTPTypes.HTTPRequest,
    body: HTTPBody?,
    retryCount: Int,
    next:
      @Sendable (HTTPTypes.HTTPRequest, HTTPBody?) async throws -> (
        HTTPTypes.HTTPResponse, HTTPBody?
      )
  ) async throws -> (HTTPTypes.HTTPResponse, HTTPBody?) {
    let result: Result<(HTTPTypes.HTTPResponse, HTTPBody?), any Error>

    do {
      result = .success(try await next(request, body))
    } catch {
      result = .failure(error)
    }

    if retryCount < retryLimit,
      shouldRetry(request: request, result: result.map(\.0))
    {
      let retryDelay =
        pow(
          Double(exponentialBackoffBase),
          Double(retryCount)
        ) * exponentialBackoffScale

      try? await clock.sleep(for: .seconds(retryDelay))

      if !Task.isCancelled {
        // This attempt's body is about to be discarded, so drain it to termination — a streamed
        // body holds its producer (a URLSession task) open until its stream finishes. Exceeding
        // the cap throws, which drops the iterator and terminates the stream just the same.
        if let responseBody = result.value?.1 {
          _ = try? await Data(collecting: responseBody, upTo: 1 << 20)
        }
        return try await retry(request, body: body, retryCount: retryCount + 1, next: next)
      }
    }

    return try result.get()
  }
}
