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
  import FoundationNetworking
#endif

/// Runs a request through `middlewares` (in order) and then the `transport`.
///
/// A cancelled task surfaces as `CancellationError`, for the head and for the body, even when
/// the transport reports it as `URLError(.cancelled)`. A non-2xx body is buffered and keeps at
/// most ``maxErrorBodyBytes``. Both apply to what the middleware chain returns; a middleware that
/// reads a body itself caps it with the same limit.
///
/// The one internal seam every sub-client sends through. Tests swap the ``ClientTransport``
/// (`ClosureTransport` in TestHelpers) instead of this type.
package struct HTTPClient: Sendable {
  /// The per-request timeout used when neither the call nor the configuration sets one.
  package static let defaultTimeout: Duration = .seconds(60)

  /// The most bytes of a non-2xx response body that are kept. The rest is dropped: an error
  /// body is only reported, and a request that reached the wrong host can answer with a page or
  /// a file.
  package static let maxErrorBodyBytes = 1 << 20

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

  /// Streaming exchange: the head returns as soon as it arrives, the body streams. A non-2xx
  /// body is read first, up to ``maxErrorBodyBytes``, and returned buffered.
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

    let head: HTTPTypes.HTTPResponse
    let responseBody: HTTPBody?
    do {
      (head, responseBody) = try await RequestTimeout.$current.withValue(timeout ?? self.timeout) {
        try await next(request, body)
      }
    } catch {
      throw Self.cancellationError(error)
    }

    // After the chain on purpose: buffering inside it would turn a failed error-body read into
    // a send failure that the retry middleware could replay.
    guard let mapped = responseBody?.mapError(Self.cancellationError) else { return (head, nil) }
    guard head.status.kind != .successful else { return (head, mapped) }
    let data = try await Data(collecting: mapped, truncatingAt: Self.maxErrorBodyBytes)
    return (head, HTTPBody(data))
  }

  /// `URLSession` reports a cancelled `Task` as `URLError(.cancelled)`. A `.cancelled` with no
  /// task cancellation behind it (a middleware cancelled the request) stays a `URLError`.
  private static func cancellationError(_ error: any Error) -> any Error {
    if let urlError = error as? URLError, urlError.code == .cancelled, Task.isCancelled {
      return CancellationError()
    }
    return error
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
