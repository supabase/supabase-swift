import Alamofire
import Foundation
import HTTPTypes

struct NoopParameter: Encodable, Sendable {}

struct APIClient: Sendable {
  let clientID: AuthClientID

  var configuration: AuthClient.Configuration {
    Dependencies[clientID].configuration
  }

  var sessionManager: SessionManager {
    Dependencies[clientID].sessionManager
  }

  var eventEmitter: AuthStateChangeEventEmitter {
    Dependencies[clientID].eventEmitter
  }

  var session: Alamofire.Session {
    Dependencies[clientID].session
  }

  private let urlQueryEncoder: any ParameterEncoding = URLEncoding.queryString
  private var defaultEncoder: any ParameterEncoder {
    JSONParameterEncoder(encoder: configuration.encoder)
  /// Error codes that should clean up local session.
  private let sessionCleanupErrorCodes: [ErrorCode] = [
    .sessionNotFound,
    .sessionExpired,
    .refreshTokenNotFound,
    .refreshTokenAlreadyUsed,
  ]
  }

  func execute<RequestBody: Encodable & Sendable>(
    _ url: URL,
    method: HTTPMethod = .get,
    headers: HTTPHeaders = [:],
    query: Parameters? = nil,
    body: RequestBody? = NoopParameter(),
    encoder: (any ParameterEncoder)? = nil
  ) throws -> DataRequest {
    var request = try URLRequest(url: url, method: method, headers: headers)

    request = try urlQueryEncoder.encode(request, with: query)
    if RequestBody.self != NoopParameter.self {
      request = try (encoder ?? defaultEncoder).encode(body, into: request)
    }

    return session.request(request)
      .validate { _, response, data in
        guard 200..<300 ~= response.statusCode else {
          return .failure(handleError(response: response, data: data ?? Data()))
        }
        return .success(())
      }
  }

  func handleError(response: HTTPURLResponse, data: Data) -> AuthError {
    guard
      let error = try? configuration.decoder.decode(
        _RawAPIErrorResponse.self,
        from: data
      )
    else {
      return .api(
        message: "Unexpected error",
        errorCode: .unexpectedFailure,
        underlyingData: data,
        underlyingResponse: response
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
      return .weakPassword(
        message: error._getErrorMessage(),
        reasons: weakPassword.reasons ?? []
      )
    } else if errorCode == .weakPassword {
      return .weakPassword(
        message: error._getErrorMessage(),
        reasons: error.weakPassword?.reasons ?? []
      )
    } else if let errorCode, sessionCleanupErrorCodes.contains(errorCode) {
      // The `session_id` inside the JWT does not correspond to a row in the
      // `sessions` table. This usually means the user has signed out, has been
      // deleted, or their session has somehow been terminated.
      await sessionManager.remove()
      eventEmitter.emit(.signedOut, session: nil)
      return .sessionMissing
    } else {
      return .api(
        message: error._getErrorMessage(),
        errorCode: errorCode ?? .unknown,
        underlyingData: data,
        underlyingResponse: response
      )
    }
  }

  private func parseResponseAPIVersion(_ response: HTTPURLResponse) -> Date? {
    guard let apiVersion = response.headers["X-Supabase-Api-Version"] else { return nil }

    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: "\(apiVersion)T00:00:00.0Z")
  }
}

// Struct for mapping all fields possibly returned by API.
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

extension Alamofire.Session {
  /// Create a new session with the same configuration but with some overridden properties.
  func newSession(
    adapters: [any RequestAdapter] = []
  ) -> Alamofire.Session {
    return Alamofire.Session(
      session: session,
      delegate: delegate,
      rootQueue: rootQueue,
      startRequestsImmediately: startRequestsImmediately,
      requestQueue: requestQueue,
      serializationQueue: serializationQueue,
      interceptor: Interceptor(
        adapters: self.interceptor != nil ? [self.interceptor!] + adapters : adapters
      ),
      serverTrustManager: serverTrustManager,
      redirectHandler: redirectHandler,
      cachedResponseHandler: cachedResponseHandler,
      eventMonitors: [eventMonitor]
    )
  }
}

struct SupabaseApiVersionAdapter: RequestAdapter {
  func adapt(
    _ urlRequest: URLRequest,
    for session: Alamofire.Session,
    completion: @escaping @Sendable (_ result: Result<URLRequest, any Error>) -> Void
  ) {
    var request = urlRequest
    request.headers["X-Supabase-Api-Version"] = apiVersions[._20240101]!.name.rawValue
    completion(.success(request))
  }
}
