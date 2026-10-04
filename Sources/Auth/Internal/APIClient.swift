import Foundation
import HTTPTypes
import Logging

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

extension HTTPClient {
  init(configuration: AuthClient.Configuration) {
    self.init(http: configuration.http, clock: configuration.clock, logger: configuration.logger)
  }

  init(http: HTTPClientConfiguration, clock: any Clock<Duration>, logger: Logging.Logger) {
    // GoTrue's writes are all safe to replay — `/token` within its refresh reuse interval — so
    // POST, PUT and DELETE are retried too. A 429 is not: GoTrue's limiters count every attempt
    // and their windows are minutes long, so replaying within seconds only burns the quota.
    var policy = RetryPolicy.default
    policy.retryableMethods.formUnion([.post, .put, .delete])
    policy.retryableStatuses.remove(429)

    self.init(
      configuration: http,
      retrying: RetryRequestInterceptor(policy: policy, clock: clock),
      appending: [LoggerInterceptor(logger: logger)])
  }
}

/// Sends requests to the Auth server with the client's default headers and maps failures to
/// ``AuthError``.
///
/// Knows nothing about sessions. `AuthAdmin` uses it standalone; ``SessionAPIClient`` layers the
/// session bookkeeping on top for the user-facing client.
struct APIClient: Sendable {
  let headers: [String: String]
  let http: HTTPClient
  let decoder: JSONDecoder

  /// Sends `request` and returns the response body.
  func execute(_ request: HTTPRequest, body: Data? = nil) async throws -> Data {
    try await send(request, body: body).data
  }

  /// Like ``execute(_:body:)`` but also returns the response head, for callers that read headers.
  func send(
    _ request: HTTPRequest, body: Data? = nil
  ) async throws -> (response: HTTPResponse, data: Data) {
    var request = request
    request.headerFields = HTTPFields(headers).merging(with: request.headerFields)

    if request.headerFields[.apiVersionHeaderName] == nil {
      request.headerFields[.apiVersionHeaderName] = apiVersions[._20240101]!.name.rawValue
    }

    let response: HTTPResponse
    let data: Data
    do {
      (response, data) = try await http.send(request, body: body)
    } catch {
      // Only the network layer's own failures are relabelled. `CancellationError`, and anything
      // thrown by user code that runs inside `send` (a custom `ClientTransport` or middleware, an `accessToken` closure),
      // propagate as themselves.
      guard let urlError = error as? URLError else { throw error }
      throw AuthError(
        kind: .transport, message: urlError.localizedDescription, underlyingError: urlError)
    }

    guard 200..<300 ~= response.status.code else {
      throw Self.error(response: response, data: data, decoder: decoder)
    }

    return (response, data)
  }

  /// Error codes GoTrue returns when the session a request was issued for no longer exists: the
  /// user signed out, was deleted, or the session was otherwise terminated.
  static let sessionCleanupErrorCodes: [ErrorCode] = [
    .sessionNotFound,
    .sessionExpired,
    .refreshTokenNotFound,
    .refreshTokenAlreadyUsed,
  ]

  /// Maps a non-2xx response to the error the caller sees.
  ///
  /// Pure: no storage or session access. A response carrying one of ``sessionCleanupErrorCodes``
  /// maps to ``AuthError/sessionMissing`` with the response attached, which is what
  /// ``AuthError/invalidatesSession`` keys off. Acting on it is the session layer's job.
  static func error(response: HTTPResponse, data: Data, decoder: JSONDecoder) -> AuthError {
    let errorResponse = HTTPErrorResponse(response, body: data)

    guard let error = try? decoder.decode(_RawAPIErrorResponse.self, from: data) else {
      let statusCode = response.status.code
      // `HTTPURLResponse` does not expose the reason phrase, so the status description is the
      // closest analog. The status code is always included because the description is localized
      // on Darwin and differs from the Linux one; the empty check is defensive only.
      let message: String
      if 500..<600 ~= statusCode {
        let description = HTTPURLResponse.localizedString(forStatusCode: statusCode)
        message = description.isEmpty ? "HTTP \(statusCode)" : "HTTP \(statusCode): \(description)"
      } else {
        message = "Unexpected response with status code \(statusCode)."
      }

      return AuthError(
        kind: .server,
        message: message,
        errorCode: .unexpectedFailure,
        response: errorResponse
      )
    }

    let responseAPIVersion = parseResponseAPIVersion(response)

    let errorCode: ErrorCode? =
      if let responseAPIVersion, responseAPIVersion >= apiVersions[._20240101]!.timestamp,
        let code = error.code
      {
        ErrorCode(code)
      } else {
        error.errorCode
      }

    if errorCode == nil, let weakPassword = error.weakPassword {
      var result = AuthError.weakPassword(
        message: error._getErrorMessage(), reasons: weakPassword.reasons ?? [])
      result.response = errorResponse
      return result
    } else if errorCode == .weakPassword {
      var result = AuthError.weakPassword(
        message: error._getErrorMessage(), reasons: error.weakPassword?.reasons ?? [])
      result.response = errorResponse
      return result
    } else if let errorCode, sessionCleanupErrorCodes.contains(errorCode) {
      var result = AuthError.sessionMissing
      result.response = errorResponse
      return result
    } else {
      return AuthError(
        kind: .server,
        message: error._getErrorMessage(),
        errorCode: errorCode ?? .unknown,
        response: errorResponse
      )
    }
  }

  private static func parseResponseAPIVersion(_ response: HTTPResponse) -> Date? {
    guard let apiVersion = response.headerFields[.apiVersionHeaderName] else { return nil }

    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: "\(apiVersion)T00:00:00.0Z")
  }
}

extension AuthError {
  /// Whether the server reported that the session the request was issued for is gone.
  ///
  /// Only ``APIClient/error(response:data:decoder:)`` produces a `sessionMissing` error with a
  /// response attached; a locally raised one (nothing in storage) has none.
  var invalidatesSession: Bool {
    kind == .sessionMissing && response != nil
  }
}

struct _RawAPIErrorResponse: Decodable {
  let msg: String?
  let message: String?
  let errorDescription: String?
  let error: String?
  let code: String?
  let errorCode: ErrorCode?
  let weakPassword: _WeakPassword?

  struct _WeakPassword: Decodable {
    let reasons: [String]?
  }

  func _getErrorMessage() -> String {
    msg ?? message ?? errorDescription ?? error ?? "Unknown"
  }
}

extension Data {
  /// Shadows `Data.decoded(as:decoder:)` from Helpers inside the Auth module so every existing
  /// decode call site throws ``AuthError`` with kind `.decoding` instead of a bare
  /// `DecodingError`. Same-module declarations win over imported ones with the same signature.
  func decoded<T: Decodable>(as _: T.Type = T.self, decoder: JSONDecoder = JSONDecoder()) throws
    -> T
  {
    do {
      return try decoder.decode(T.self, from: self)
    } catch {
      throw AuthError(
        kind: .decoding,
        message: "Failed to decode the Auth response as \(T.self).",
        underlyingError: error
      )
    }
  }
}
