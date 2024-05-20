import Foundation

/// Extracts parameters encoded in the URL both in the query and fragment.
func extractParams(from url: URL) -> [String: String] {
  guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
    return [:]
  }

  var result: [String: String] = [:]

  if let fragment = components.fragment {
    let items = extractParams(from: fragment)
    for item in items {
      result[item.name] = item.value
    }
  }

  if let items = components.queryItems {
    for item in items {
      result[item.name] = item.value
    }
  }

  return result
}

private func extractParams(from fragment: String) -> [URLQueryItem] {
  let components =
    fragment
      .split(separator: "&")
      .map { $0.split(separator: "=") }

  return
    components
      .compactMap {
        $0.count == 2
          ? URLQueryItem(name: String($0[0]), value: String($0[1]))
          : nil
      }
}

func decode(jwt: String) throws -> [String: Any] {
  let parts = jwt.split(separator: ".")
  guard parts.count == 3 else {
    throw AuthError.malformedJWT
  }

  let payload = String(parts[1])
  guard let data = base64URLDecode(payload) else {
    throw AuthError.malformedJWT
  }
  let json = try JSONSerialization.jsonObject(with: data, options: [])
  guard let decodedPayload = json as? [String: Any] else {
    throw AuthError.malformedJWT
  }
  return decodedPayload
}

private func base64URLDecode(_ value: String) -> Data? {
  var base64 = value.replacingOccurrences(of: "-", with: "+")
    .replacingOccurrences(of: "_", with: "/")
  let length = Double(base64.lengthOfBytes(using: .utf8))
  let requiredLength = 4 * ceil(length / 4.0)
  let paddingLength = requiredLength - length
  if paddingLength > 0 {
    let padding = "".padding(toLength: Int(paddingLength), withPad: "=", startingAt: 0)
    base64 = base64 + padding
  }
  return Data(base64Encoded: base64, options: .ignoreUnknownCharacters)
}

struct RetryLimitReachedError: Error {}

/// Retry an operation while `limit` is not reached and `isRetryable` returns true.
func retry<T>(
  limit: Int = .max,
  _ operation: @Sendable (_ attempt: Int) async throws -> T,
  isRetryable: @Sendable (_ attempt: Int, _ error: any Error) -> Bool
) async throws -> T {
  for attempt in 0 ..< limit {
    do {
      return try await operation(attempt)
    } catch {
      if !isRetryable(attempt, error) {
        throw error
      }
    }
  }

  throw RetryLimitReachedError()
}

// List of default retryable status codes taken from Alamofire.
// https://github.com/Alamofire/Alamofire/blob/f455c2975872ccd2d9c81594c658af65716e9b9a/Source/Features/RetryPolicy.swift#L51
let retryableStatusCode: Set<Int> = [
  408, // Request Timeout
  500, // Internal Server Error
  502, // Bad Gateway
  503, // Service Unavailable
  504, // Gateway Timeout
]

// List of default retryable URLError codes taken from Alamofire.
// https://github.com/Alamofire/Alamofire/blob/f455c2975872ccd2d9c81594c658af65716e9b9a/Source/Features/RetryPolicy.swift#L59
let retryableURLErrorCodes: Set<URLError.Code> = [
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

func isRetryableError(_ error: any Error) -> Bool {
  if let urlError = error as? URLError {
    return retryableURLErrorCodes.contains(urlError.code)
  }

  if let authError = error as? AuthError,
     case let .api(apiError) = authError,
     let code = apiError.code
  {
    return retryableStatusCode.contains(code)
  }

  return false
}
