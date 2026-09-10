//
//  Middlewares.swift
//  Supabase
//
//  Created by Guilherme Souza on 09/09/26.
//

import HTTPTypes
import Helpers

/// Sets the W3C `traceparent` header from the active OpenTelemetry span. See ``TraceContext``.
struct TraceContextMiddleware: ClientMiddleware {
  func intercept(
    _ request: HTTPTypes.HTTPRequest,
    body: HTTPBody?,
    next:
      @Sendable (HTTPTypes.HTTPRequest, HTTPBody?) async throws -> (
        HTTPTypes.HTTPResponse, HTTPBody?
      )
  ) async throws -> (HTTPTypes.HTTPResponse, HTTPBody?) {
    var request = request
    if let traceparent = TraceContext.traceParentHeader() {
      request.headerFields[.traceparent] = traceparent
    }
    return try await next(request, body)
  }
}

/// Resolves the current access token and sends it as `Authorization: Bearer`.
struct AccessTokenMiddleware: ClientMiddleware {
  let getAccessToken: @Sendable () async throws -> String?

  func intercept(
    _ request: HTTPTypes.HTTPRequest,
    body: HTTPBody?,
    next:
      @Sendable (HTTPTypes.HTTPRequest, HTTPBody?) async throws -> (
        HTTPTypes.HTTPResponse, HTTPBody?
      )
  ) async throws -> (HTTPTypes.HTTPResponse, HTTPBody?) {
    var request = request
    if let token = try await getAccessToken() {
      request.headerFields[.authorization] = "Bearer \(token)"
    }
    return try await next(request, body)
  }
}

extension HTTPField.Name {
  fileprivate static let traceparent = HTTPField.Name("traceparent")!
}
