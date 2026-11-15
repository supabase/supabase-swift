import HTTPTypes
import Helpers

/// Appends `value` to the header `name`, comma-separated, so a test can read the order the
/// middlewares ran in.
struct HeaderMiddleware: ClientMiddleware {
  let name: String
  let value: String

  func intercept(
    _ request: HTTPTypes.HTTPRequest,
    body: HTTPBody?,
    next:
      @Sendable (HTTPTypes.HTTPRequest, HTTPBody?) async throws -> (
        HTTPTypes.HTTPResponse, HTTPBody?
      )
  ) async throws -> (HTTPTypes.HTTPResponse, HTTPBody?) {
    var request = request
    let field = HTTPField.Name(name)!
    request.headerFields[field] = [request.headerFields[field], value].compactMap { $0 }
      .joined(separator: ",")
    return try await next(request, body)
  }
}
