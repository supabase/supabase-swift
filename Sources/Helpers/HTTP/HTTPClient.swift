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
  /// The per-request timeout used when neither the call nor the configuration sets one.
  package static let defaultTimeout: Duration = .seconds(60)

  let transport: any ClientTransport
  let middlewares: [any ClientMiddleware]
  /// The timeout applied to a request that does not pass its own `timeout:`.
  let timeout: Duration

  package init(
    transport: any ClientTransport,
    middlewares: [any ClientMiddleware] = [],
    timeout: Duration = HTTPClient.defaultTimeout
  ) {
    self.transport = transport
    self.middlewares = middlewares
    self.timeout = timeout
  }

  /// Buffered exchange: uploads `body` from memory and collects the whole response body.
  ///
  /// `timeout` overrides the client-wide ``timeout`` for this one request.
  package func send(
    _ request: HTTPTypes.HTTPRequest,
    body: Data? = nil,
    timeout: Duration? = nil
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
    timeout: Duration? = nil
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

    return try await RequestTimeout.$current.withValue(timeout ?? self.timeout) {
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
