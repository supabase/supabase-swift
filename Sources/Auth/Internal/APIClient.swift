import _Helpers
import Foundation

extension HTTPClient {
  init(configuration: AuthClient.Configuration) {
    self.init(logger: configuration.logger, fetchHandler: configuration.fetch)
  }
}

struct APIClient: Sendable {
  var execute: @Sendable (_ request: Request) async throws -> Response
}

extension APIClient {
  init(http: HTTPClient) {
    var configuration: AuthClient.Configuration {
      Current.configuration
    }

    self.init { request in
      var request = request
      request.headers.merge(configuration.headers) { r, _ in r }

      let response = try await http.fetch(request, baseURL: configuration.url)

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
        let postgrestError = try configuration.decoder.decode(
          PostgrestError.self,
          from: response.data
        )
        throw postgrestError
      }

      return response
    }
  }
}

extension APIClient {
  @discardableResult
  func authorizedExecute(_ request: Request) async throws -> Response {
    var sessionManager: SessionManager {
      Current.sessionManager
    }

    let session = try await sessionManager.session()

    var request = request
    request.headers["Authorization"] = "Bearer \(session.accessToken)"

    return try await execute(request)
  }
}
