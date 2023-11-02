import Foundation
@_spi(Internal) import _Helpers

actor APIClient {
  private var configuration: GoTrueClient.Configuration {
    Dependencies.current.value!.configuration
  }

  private var sessionManager: SessionManager {
    Dependencies.current.value!.sessionManager
  }

  let http: HTTPClient

  init(http: HTTPClient) {
    self.http = http
  }

  @discardableResult
  func authorizedExecute(_ request: Request) async throws -> Response {
    let session = try await sessionManager.session()

    var request = request
    request.headers["Authorization"] = "Bearer \(session.accessToken)"

    return try await execute(request)
  }

  @discardableResult
  func execute(_ request: Request) async throws -> Response {
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
}
