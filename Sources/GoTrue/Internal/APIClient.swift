import Foundation
@_spi(Internal) import _Helpers

struct APIClient: Sendable {
  var execute: @Sendable (_ request: Request) async throws -> Response
}

extension APIClient {
  static func live(http: HTTPClient) -> Self {
    var configuration: GoTrueClient.Configuration {
      Dependencies.current.value!.configuration
    }

    return APIClient(
      execute: { request in
        var request = request
        request.headers.merge(configuration.headers) { r, _ in r }

        let response = try await http.fetch(request, baseURL: configuration.url)

        guard (200 ..< 300).contains(response.statusCode) else {
          let apiError = try configuration.decoder.decode(
            GoTrueError.APIError.self,
            from: response.data
          )
          throw GoTrueError.api(apiError)
        }

        return response
      }
    )
  }
}

extension APIClient {
  @discardableResult
  func authorizedExecute(_ request: Request) async throws -> Response {
    let session = try await Dependencies.current.value!.sessionManager.session()

    var request = request
    request.headers["Authorization"] = "Bearer \(session.accessToken)"

    return try await execute(request)
  }
}
