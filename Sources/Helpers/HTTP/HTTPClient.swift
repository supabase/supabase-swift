//
//  HTTPClient.swift
//
//
//  Created by Guilherme Souza on 30/04/24.
//

package import Foundation
package import HTTPTypes
import HTTPTypesFoundation

/// Runs a request through `middlewares` (in order) and then the `transport`.
///
/// The one internal seam every sub-client sends through. Tests swap the ``ClientTransport``
/// (`ClosureTransport` in TestHelpers) instead of this type.
package struct HTTPClient: Sendable {
  let transport: any ClientTransport
  let middlewares: [any ClientMiddleware]

  package init(transport: any ClientTransport, middlewares: [any ClientMiddleware] = []) {
    self.transport = transport
    self.middlewares = middlewares
  }

  /// Buffered exchange: uploads `body` from memory and collects the whole response body.
  package func send(
    _ request: HTTPTypes.HTTPRequest,
    body: Data? = nil,
    timeout: TimeInterval = 60
  ) async throws -> (HTTPTypes.HTTPResponse, Data) {
    let (head, responseBody) = try await stream(
      request, body: body.map { HTTPBody($0) }, timeout: timeout)
    var data = Data()
    if let responseBody { data = try await Data(collecting: responseBody, upTo: .max) }
    return (head, data)
  }

  /// Streaming exchange: the head returns as soon as it arrives, the body streams.
  ///
  /// A request with a body and no `Content-Type` is sent as JSON. The header is set before the
  /// middleware chain runs, so middlewares see the request the transport sees.
  package func stream(
    _ request: HTTPTypes.HTTPRequest,
    body: HTTPBody? = nil,
    timeout: TimeInterval = 60
  ) async throws -> (HTTPTypes.HTTPResponse, HTTPBody?) {
    var request = request
    if body != nil, request.headerFields[.contentType] == nil {
      request.headerFields[.contentType] = "application/json"
    }

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

    return try await RequestTimeout.$current.withValue(timeout) {
      try await next(request, body)
    }
  }
}

extension HTTPTypes.HTTPRequest {
  /// Builds a request head with `query` appended to `url` using the SDK's percent-encoding rules.
  package init(
    method: Method,
    url: URL,
    query: [URLQueryItem],
    headerFields: HTTPFields = [:]
  ) {
    self.init(method: method, url: url.appendingQueryItems(query), headerFields: headerFields)
  }
}
