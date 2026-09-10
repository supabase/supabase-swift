//
//  HTTPClient.swift
//
//
//  Created by Guilherme Souza on 30/04/24.
//

package import Foundation
package import HTTPTypes
import HTTPTypesFoundation

#if canImport(FoundationNetworking)
  package import FoundationNetworking
#endif

/// The internal seam every sub-client sends through. `HTTPClient` is the real one;
/// `HTTPClientMock` in TestHelpers is the test double.
package protocol HTTPClientType: Sendable {
  /// Buffered exchange.
  func send(_ request: HTTPRequest) async throws -> HTTPResponse
  /// Streaming exchange: the head returns as soon as it arrives, the body streams.
  func stream(_ request: HTTPRequest) async throws -> (HTTPTypes.HTTPResponse, HTTPBody?)
}

extension HTTPClientType {
  /// Buffers the exchange through ``send(_:)`` and re-wraps it as a head plus body.
  ///
  /// The default for clients that have no streaming path of their own (the test doubles).
  /// ``HTTPClient`` overrides it with a genuinely streaming implementation.
  package func stream(_ request: HTTPRequest) async throws -> (HTTPTypes.HTTPResponse, HTTPBody?) {
    let response = try await send(request)
    guard let head = response.underlyingResponse.httpResponse else {
      throw URLError(.badServerResponse)
    }
    return (head, response.data.isEmpty ? nil : HTTPBody(response.data))
  }
}

/// Runs a request through `middlewares` (in order) and then the `transport`.
package struct HTTPClient: HTTPClientType {
  let transport: any ClientTransport
  let middlewares: [any ClientMiddleware]

  package init(transport: any ClientTransport, middlewares: [any ClientMiddleware]) {
    self.transport = transport
    self.middlewares = middlewares
  }

  package func send(_ request: HTTPRequest) async throws -> HTTPResponse {
    let (head, body) = try await stream(request)
    var data = Data()
    if let body { data = try await Data(collecting: body, upTo: .max) }
    return try HTTPResponse(data: data, head: head, url: request.finalURL)
  }

  package func stream(_ request: HTTPRequest) async throws -> (HTTPTypes.HTTPResponse, HTTPBody?) {
    let (httpRequest, body) = request.httpRequestAndBody

    var next:
      @Sendable (HTTPTypes.HTTPRequest, HTTPBody?) async throws -> (
        HTTPTypes.HTTPResponse, HTTPBody?
      ) = { [transport] request, body in
        try await transport.send(request, body: body)
      }
    for middleware in middlewares.reversed() {
      let tmp = next
      next = { try await middleware.intercept($0, body: $1, next: tmp) }
    }

    return try await RequestTimeout.$current.withValue(request.timeoutInterval) {
      try await next(httpRequest, body)
    }
  }
}
