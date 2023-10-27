import Foundation
@_spi(Internal) import _Helpers

actor APIClient {
  private var configuration: GoTrueClient.Configuration {
    Dependencies.current.value!.configuration
  }

  private var sessionManager: SessionManager {
    Dependencies.current.value!.sessionManager
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
    let urlRequest = try request.urlRequest(withBaseURL: configuration.url)

    let (data, response) = try await configuration.fetch(urlRequest)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw URLError(.badServerResponse)
    }

    guard (200..<300).contains(httpResponse.statusCode) else {
      let apiError = try configuration.decoder.decode(GoTrueError.APIError.self, from: data)
      throw GoTrueError.api(apiError)
    }

    return Response(data: data, response: httpResponse)
  }
}
