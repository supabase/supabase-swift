//
//  SupabaseMiddleware.swift
//  Helpers
//

import Foundation
import HTTPTypes
import OpenAPIRuntime

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// `ClientMiddleware` that injects static headers and a dynamic Bearer token
/// into every outgoing request for generated Supabase API clients.
package struct SupabaseMiddleware: ClientMiddleware, Sendable {
  private let headers: [String: String]
  private let tokenProvider: (@Sendable () async throws -> String?)?

  package init(
    headers: [String: String],
    tokenProvider: (@Sendable () async throws -> String?)? = nil
  ) {
    self.headers = headers
    self.tokenProvider = tokenProvider
  }

  package func intercept(
    _ request: HTTPTypes.HTTPRequest,
    body: HTTPBody?,
    baseURL: URL,
    operationID: String,
    next: @Sendable (HTTPTypes.HTTPRequest, HTTPBody?, URL) async throws -> (
      HTTPTypes.HTTPResponse, HTTPBody?
    )
  ) async throws -> (HTTPTypes.HTTPResponse, HTTPBody?) {
    var request = request
    for (key, value) in headers {
      if let name = HTTPField.Name(key), request.headerFields[name] == nil {
        request.headerFields[name] = value
      }
    }
    if request.headerFields[.authorization] == nil,
      let token = try await tokenProvider?()
    {
      request.headerFields[.authorization] = "Bearer \(token)"
    }
    return try await next(request, body, baseURL)
  }
}
