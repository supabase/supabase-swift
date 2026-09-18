import Foundation
import HTTPTypes

extension HTTPClient {
  init(configuration: AuthClient.Configuration) {
    // GoTrue's writes are all safe to replay — `/token` within its refresh reuse interval — so
    // POST, PUT and DELETE are retried too. A 429 is not: GoTrue's limiters count every attempt
    // and their windows are minutes long, so replaying within seconds only burns the quota.
    var policy = RetryPolicy.default
    policy.retryableMethods.formUnion([.post, .put, .delete])
    policy.retryableStatuses.remove(429)

    self.init(
      configuration: configuration.http,
      retrying: RetryRequestInterceptor(policy: policy, clock: configuration.clock),
      appending: [LoggerInterceptor(logger: configuration.logger)])
  }
}

struct APIClient: Sendable {
  let clientID: AuthClientID

  var configuration: AuthClient.Configuration {
    Dependencies[clientID].configuration
  }

  var sessionManager: SessionManager {
    Dependencies[clientID].sessionManager
  }

  var sessionStorage: SessionStorage {
    Dependencies[clientID].sessionStorage
  }

  var eventEmitter: AuthStateChangeEventEmitter {
    Dependencies[clientID].eventEmitter
  }

  var http: HTTPClient {
    Dependencies[clientID].http
  }

  /// Error codes that should clean up local session.
  private let sessionCleanupErrorCodes: [ErrorCode] = [
    .sessionNotFound,
    .sessionExpired,
    .refreshTokenNotFound,
    .refreshTokenAlreadyUsed,
  ]

  /// Sends `request` with the client's default headers and returns the response body.
  ///
  /// `session` is the session the request is issued for, when the caller has one. It scopes the
  /// session cleanup that a `sessionCleanupErrorCodes` response triggers — see
  /// ``send(_:body:for:)``.
  func execute(
    _ request: HTTPRequest, body: Data? = nil, for session: Session? = nil
  ) async throws -> Data {
    try await send(request, body: body, for: session).data
  }

  /// Like ``execute(_:body:for:)`` but also returns the response head, for callers that read
  /// headers.
  ///
  /// Pass `session` whenever the caller knows which session the request belongs to. A response
  /// carrying a `sessionCleanupErrorCodes` code then only clears storage if that session is still
  /// the stored one, so a request that outlived a sign-out cannot sign out whoever signed in
  /// after it. Callers with no session of their own (sign-in, sign-up, `/logout`) pass `nil` and
  /// keep the unconditional cleanup they have always had.
  func send(
    _ request: HTTPRequest, body: Data? = nil, for session: Session? = nil
  ) async throws -> (response: HTTPResponse, data: Data) {
    var request = request
    request.headerFields = HTTPFields(configuration.headers).merging(with: request.headerFields)

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
      throw await handleError(response: response, data: data, for: session)
    }

    return (response, data)
  }

  @discardableResult
  func authorizedExecute(_ request: HTTPRequest, body: Data? = nil) async throws -> Data {
    var sessionManager: SessionManager {
      Dependencies[clientID].sessionManager
    }

    let session = try await sessionManager.session()

    var request = request
    request.headerFields[.authorization] = "Bearer \(session.accessToken)"

    return try await execute(request, body: body, for: session)
  }

  func handleError(
    response: HTTPResponse, data: Data, for session: Session?
  ) async -> AuthError {
    let errorResponse = HTTPErrorResponse(response, body: data)

    guard
      let error = try? configuration.resolvedDecoder.decode(_RawAPIErrorResponse.self, from: data)
    else {
      return AuthError(
        kind: .unexpectedResponse,
        message: "Unexpected response with status code \(response.status.code).",
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
      // The `session_id` inside the JWT does not correspond to a row in the
      // `sessions` table. This usually means the user has signed out, has been
      // deleted, or their session has somehow been terminated.
      //
      // Only `session`'s own storage slot may be cleared. A request that was still in flight when
      // the user signed out — and another user signed in — would otherwise delete the session
      // that replaced it and sign that user out.
      if !sessionStorage.changed(since: session) {
        await sessionManager.remove()
        eventEmitter.emit(.signedOut, session: nil)
      }
      var result = AuthError.sessionMissing
      result.response = errorResponse
      return result
    } else {
      return AuthError(
        kind: .api,
        message: error._getErrorMessage(),
        errorCode: errorCode ?? .unknown,
        response: errorResponse
      )
    }
  }

  private func parseResponseAPIVersion(_ response: HTTPResponse) -> Date? {
    guard let apiVersion = response.headerFields[.apiVersionHeaderName] else { return nil }

    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: "\(apiVersion)T00:00:00.0Z")
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
