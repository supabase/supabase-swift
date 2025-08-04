import HTTPTypes
import OpenAPIRuntime

#if canImport(Darwin)
  import struct Foundation.URL
#else
  @preconcurrency import struct Foundation.URL
#endif

/// A client that can send HTTP requests and receive HTTP responses.
struct Client: Sendable {

  /// The URL of the server, used as the base URL for requests made by the
  /// client.
  let serverURL: URL

  /// A type capable of sending HTTP requests and receiving HTTP responses.
  var transport: any ClientTransport

  /// The middlewares to be invoked before the transport.
  var middlewares: [any ClientMiddleware]

  /// Creates a new client.
  init(
    serverURL: URL,
    transport: any ClientTransport,
    middlewares: [any ClientMiddleware] = []
  ) {
    self.serverURL = serverURL
    self.transport = transport
    self.middlewares = middlewares
  }

  /// Sends the HTTP request and returns the HTTP response.
  ///
  /// - Parameters:
  ///   - request: The HTTP request to send.
  ///   - body: The HTTP request body to send.
  /// - Returns: The HTTP response and its body.
  /// - Throws: An error if any part of the HTTP operation process fails.
  func send(
    _ request: HTTPTypes.HTTPRequest,
    body: HTTPBody? = nil
  ) async throws -> (HTTPTypes.HTTPResponse, HTTPBody?) {
    let baseURL = serverURL
    var next:
      @Sendable (HTTPTypes.HTTPRequest, HTTPBody?, URL) async throws -> (
        HTTPTypes.HTTPResponse, HTTPBody?
      ) = {
        (_request, _body, _url) in
        try await transport.send(
          _request,
          body: _body,
          baseURL: _url,
          operationID: ""
        )
      }
    for middleware in middlewares.reversed() {
      let tmp = next
      next = { (_request, _body, _url) in
        try await middleware.intercept(
          _request,
          body: _body,
          baseURL: _url,
          operationID: "",
          next: tmp
        )
      }
    }
    return try await next(request, body, baseURL)
  }
}
