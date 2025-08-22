import Alamofire
import Foundation
import HTTPTypes

struct NoopParameter: Encodable, Sendable {}

struct APIClient: Sendable {
  let clientID: AuthClientID

  var configuration: AuthClient.Configuration {
    Dependencies[clientID].configuration
  }

  var session: Alamofire.Session {
    Dependencies[clientID].session
  }

  private let urlQueryEncoder: any ParameterEncoding = URLEncoding.queryString
  private var defaultEncoder: any ParameterEncoder {
    JSONParameterEncoder(encoder: configuration.encoder)
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
    } else if errorCode == .sessionNotFound {
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
    adapter: (any RequestAdapter)? = nil
  ) -> Alamofire.Session {
    return Alamofire.Session(
      session: session,
      delegate: delegate,
      rootQueue: rootQueue,
      startRequestsImmediately: startRequestsImmediately,
      requestQueue: requestQueue,
      serializationQueue: serializationQueue,
      interceptor: Interceptor(adapters: [self.interceptor, adapter].compactMap { $0 }),
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
