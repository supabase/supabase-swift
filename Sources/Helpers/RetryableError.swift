//
//  RetryableError.swift
//  Supabase
//
//  Created by Guilherme Souza on 15/10/24.
//
import Foundation

/// An error type that can be retried.
package protocol RetryableError: Error {
  /// Whether this error instance should be retried or not.
  var shouldRetry: Bool { get }
}

extension URLError: RetryableError {
  package var shouldRetry: Bool {
    defaultRetryableURLErrorCodes.contains(code)
  }
}

/// The default set of retryable URL error codes.
package let defaultRetryableURLErrorCodes: Set<URLError.Code> = [
  .backgroundSessionInUseByAnotherProcess, .backgroundSessionWasDisconnected,
  .badServerResponse, .callIsActive, .cannotConnectToHost, .cannotFindHost,
  .cannotLoadFromNetwork, .dataNotAllowed, .dnsLookupFailed,
  .downloadDecodingFailedMidStream, .downloadDecodingFailedToComplete,
  .internationalRoamingOff, .networkConnectionLost, .notConnectedToInternet,
  .secureConnectionFailed, .serverCertificateHasBadDate,
  .serverCertificateNotYetValid, .timedOut,
]

/// The default set of retryable HTTP status codes.
package let defaultRetryableHTTPStatusCodes: Set<Int> = [
  408, 500, 502, 503, 504,
]
