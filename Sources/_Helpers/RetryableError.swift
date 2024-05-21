//
//  RetryableError.swift
//
//
//  Created by Guilherme Souza on 20/05/24.
//

import Foundation

package protocol RetryableError: Error {
  var isRetryable: Bool { get }
}

extension RetryableError {
  package var isRetryable: Bool { false }
}

extension Error {
  package var isRetryable: Bool {
    guard let retryableError = self as? any RetryableError else {
      NSLog("\(type(of: self)) does not conform to RetryableError.")
      return false
    }

    return retryableError.isRetryable
  }
}

extension CancellationError: RetryableError {
  package var isRetryable: Bool { false }
}

// List of default retryable status codes taken from Alamofire.
// https://github.com/Alamofire/Alamofire/blob/f455c2975872ccd2d9c81594c658af65716e9b9a/Source/Features/RetryPolicy.swift#L51
package let retryableStatusCode: Set<Int> = [
  408, // Request Timeout
  500, // Internal Server Error
  502, // Bad Gateway
  503, // Service Unavailable
  504, // Gateway Timeout
]

// List of default retryable URLError codes taken from Alamofire.
// https://github.com/Alamofire/Alamofire/blob/f455c2975872ccd2d9c81594c658af65716e9b9a/Source/Features/RetryPolicy.swift#L59
package let retryableURLErrorCodes: Set<URLError.Code> = [
  .backgroundSessionInUseByAnotherProcess,
  .backgroundSessionWasDisconnected,
  .badServerResponse,
  .callIsActive,
  .cannotConnectToHost,
  .cannotFindHost,
  .cannotLoadFromNetwork,
  .dataNotAllowed,
  .dnsLookupFailed,
  .downloadDecodingFailedMidStream,
  .downloadDecodingFailedToComplete,
  .internationalRoamingOff,
  .networkConnectionLost,
  .notConnectedToInternet,
  .secureConnectionFailed,
  .serverCertificateHasBadDate,
  .serverCertificateNotYetValid,
  .timedOut,
]

extension URLError: RetryableError {
  package var isRetryable: Bool {
    retryableURLErrorCodes.contains(code)
  }
}
