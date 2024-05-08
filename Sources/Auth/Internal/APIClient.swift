import _Helpers
import Foundation

extension HTTPClient {
  init(configuration: AuthClient.Configuration) {
    var interceptors: [any HTTPClientInterceptor] = []
    if let logger = configuration.logger {
      interceptors.append(LoggerInterceptor(logger: logger))
    }

    self.init(fetch: configuration.fetch, interceptors: interceptors)
  }
}

struct APIClient: Sendable {
  var configuration: AuthClient.Configuration {
    Current.configuration
  }

  var http: any HTTPClientType {
    Current.http
  }

  func execute(_ request: HTTPRequest) async throws -> HTTPResponse {
    var request = request
    request.headers.merge(with: HTTPHeaders(configuration.headers))

    let response = try await http.send(request)

    guard (200 ..< 300).contains(response.statusCode) else {
      if let apiError = try? configuration.decoder.decode(
        AuthError.APIError.self,
        from: response.data
      ) {
        throw AuthError.api(apiError)
      }

      /// There are some GoTrue endpoints that can return a `PostgrestError`, for example the
      /// ``AuthAdmin/deleteUser(id:shouldSoftDelete:)`` that could return an error in case the
      /// user is referenced by other schemas.
      if let postgrestError = try? configuration.decoder.decode(
        PostgrestError.self,
        from: response.data
      ) {
        throw postgrestError
      }

      throw HTTPError(data: response.data, response: response.underlyingResponse)
    }

    return response
  }

  @discardableResult
  func authorizedExecute(_ request: HTTPRequest) async throws -> HTTPResponse {
    var sessionManager: SessionManager {
      Current.sessionManager
    }

    let session = try await sessionManager.session()

    var request = request
    request.headers["Authorization"] = "Bearer \(session.accessToken)"

    return try await execute(request)
  }
}
