import Foundation
import Helpers

extension HTTPClient {
  init(configuration: AuthClient.Configuration) {
    var interceptors: [any HTTPClientInterceptor] = []
    if let logger = configuration.logger {
      interceptors.append(LoggerInterceptor(logger: logger))
    }

    interceptors.append(
      RetryRequestInterceptor(
        retryableHTTPMethods: RetryRequestInterceptor.defaultRetryableHTTPMethods.union(
          [.post] // Add POST method so refresh token are also retried.
        )
      )
    )

    self.init(fetch: configuration.fetch, interceptors: interceptors)
  }
}

struct APIClient: Sendable {
  let clientID: AuthClientID

  var configuration: AuthClient.Configuration {
    Dependencies[clientID].configuration
  }

  var http: any HTTPClientType {
    Dependencies[clientID].http
  }

  func execute(_ request: HTTPRequest) async throws -> HTTPResponse {
    var request = request
    request.headers = HTTPHeaders(configuration.headers).merged(with: request.headers)

    if request.headers[API_VERSION_HEADER_NAME] == nil {
      request.headers[API_VERSION_HEADER_NAME] = API_VERSIONS[._20240101]!.name.rawValue
    }

    let response = try await http.send(request)

    guard 200 ..< 300 ~= response.statusCode else {
      throw handleError(response: response)
    }

    return response
  }

  @discardableResult
  func authorizedExecute(_ request: HTTPRequest) async throws -> HTTPResponse {
    var sessionManager: SessionManager {
      Dependencies[clientID].sessionManager
    }

    let session = try await sessionManager.session()

    var request = request
    request.headers["Authorization"] = "Bearer \(session.accessToken)"

    return try await execute(request)
  }

  func handleError(response: HTTPResponse) -> AuthError {
    guard let error = try? response.decoded(
      as: _RawAPIErrorResponse.self,
      decoder: configuration.decoder
    ) else {
      return .api(
        message: "Unexpected error",
        errorCode: .UnexpectedFailure,
        underlyingData: response.data,
        underlyingResponse: response.underlyingResponse
      )
    }

    let responseAPIVersion = parseResponseAPIVersion(response)

    let errorCode: ErrorCode? = if let responseAPIVersion, responseAPIVersion >= API_VERSIONS[._20240101]!.timestamp, let code = error.code {
      ErrorCode(code)
    } else {
      error.errorCode
    }

    if errorCode == nil, let weakPassword = error.weakPassword {
      return .weakPassword(
        message: error._getErrorMessage(),
        reasons: weakPassword.reasons ?? []
      )
    } else if errorCode == .WeakPassword {
      return .weakPassword(
        message: error._getErrorMessage(),
        reasons: error.weakPassword?.reasons ?? []
      )
    } else if errorCode == .SessionNotFound {
      return .sessionMissing
    } else {
      return .api(
        message: error._getErrorMessage(),
        errorCode: errorCode ?? .Unknown,
        underlyingData: response.data,
        underlyingResponse: response.underlyingResponse
      )
    }
  }

  private func parseResponseAPIVersion(_ response: HTTPResponse) -> Date? {
    guard let apiVersion = response.headers[API_VERSION_HEADER_NAME] else { return nil }
    return ISO8601DateFormatter().date(from: "\(apiVersion)T00:00:00.0Z")
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
