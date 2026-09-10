//
//  ClientTransport.swift
//  Helpers
//
//  Created by Guilherme Souza on 09/09/26.
//

package import Foundation
public import HTTPTypes

/// Performs one HTTP exchange. The single seam between the SDK and the network.
///
/// Implement this to route every request made by any Supabase sub-client through your own
/// networking stack, or to simulate the network in tests:
///
/// ```swift
/// struct RecordingTransport: ClientTransport {
///   func send(_ request: HTTPRequest, body: HTTPBody?) async throws -> (HTTPResponse, HTTPBody?) {
///     (HTTPResponse(status: .ok), HTTPBody(Data("[]".utf8)))
///   }
/// }
/// let client = SupabaseClient(
///   supabaseURL: url, supabaseKey: key,
///   options: .init(global: .init(transport: RecordingTransport()))
/// )
/// ```
///
/// The default implementation is ``URLSessionTransport``.
public protocol ClientTransport: Sendable {
  /// Sends a request and returns the response head as soon as it arrives. The body streams.
  ///
  /// - Parameters:
  ///   - request: The head: method, URL (scheme, authority and path pseudo-headers) and
  ///     header fields.
  ///   - body: The request body, or `nil` for a bodiless request. Check
  ///     ``HTTPBody/length`` to pick `Content-Length` versus chunked framing.
  /// - Returns: The response head and body. Return `nil` for an empty body.
  func send(_ request: HTTPTypes.HTTPRequest, body: HTTPBody?) async throws -> (
    HTTPTypes.HTTPResponse, HTTPBody?
  )
}

/// Observes or rewrites requests and responses on their way to and from a ``ClientTransport``.
///
/// Middlewares run in array order for requests and in reverse order for responses. Call
/// `next` exactly once to continue the chain, or return without calling it to short-circuit.
///
/// ```swift
/// struct UserAgentMiddleware: ClientMiddleware {
///   func intercept(
///     _ request: HTTPRequest, body: HTTPBody?,
///     next: @Sendable (HTTPRequest, HTTPBody?) async throws -> (HTTPResponse, HTTPBody?)
///   ) async throws -> (HTTPResponse, HTTPBody?) {
///     var request = request
///     request.headerFields[.userAgent] = "my-app/1.0"
///     return try await next(request, body)
///   }
/// }
/// ```
///
/// A middleware that retries must check ``HTTPBody/iterationBehavior`` and skip the retry
/// when it is ``HTTPBody/IterationBehavior/single``.
public protocol ClientMiddleware: Sendable {
  /// Handles one exchange.
  ///
  /// - Parameters:
  ///   - request: The outgoing request head.
  ///   - body: The outgoing body, if any.
  ///   - next: The rest of the chain, ending in the transport.
  func intercept(
    _ request: HTTPTypes.HTTPRequest,
    body: HTTPBody?,
    next:
      @Sendable (HTTPTypes.HTTPRequest, HTTPBody?) async throws -> (
        HTTPTypes.HTTPResponse, HTTPBody?
      )
  ) async throws -> (HTTPTypes.HTTPResponse, HTTPBody?)
}

/// Carries the internal per-request timeout from `HTTPClient` to ``URLSessionTransport``.
///
/// `HTTPTypes.HTTPRequest` has no timeout field, and this SDK promises per-request timeouts
/// (`FunctionInvokeOptions.timeoutInterval`). A task local flows through every middleware
/// without appearing in the public protocol. Custom transports own their own timeouts and can
/// ignore it.
package enum RequestTimeout {
  @TaskLocal package static var current: TimeInterval?
}
