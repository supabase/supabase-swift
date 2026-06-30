//
//  SupabaseClientTransport.swift
//  Helpers
//

import Foundation
import HTTPTypes
import OpenAPIRuntime
import OpenAPIURLSession

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// `ClientTransport` for generated Supabase API clients.
///
/// Wraps `URLSessionTransport` from `swift-openapi-urlsession` for correct streaming,
/// and injects a Bearer token when no `Authorization` header is already present.
/// Does not depend on `_HTTPClient`.
package struct SupabaseClientTransport: ClientTransport, Sendable {
  private let inner: URLSessionTransport
  package let tokenProvider: (@Sendable () async throws -> String?)?

  package init(
    session: URLSession = URLSession(configuration: .default),
    tokenProvider: (@Sendable () async throws -> String?)? = nil
  ) {
    self.inner = URLSessionTransport(configuration: .init(session: session))
    self.tokenProvider = tokenProvider
  }

  package func send(
    _ request: HTTPTypes.HTTPRequest,
    body: HTTPBody?,
    baseURL: URL,
    operationID: String
  ) async throws -> (HTTPTypes.HTTPResponse, HTTPBody?) {
    var request = request
    if request.headerFields[HTTPField.Name.authorization] == nil,
      let token = try await tokenProvider?()
    {
      request.headerFields[HTTPField.Name.authorization] = "Bearer \(token)"
    }
    return try await inner.send(request, body: body, baseURL: baseURL, operationID: operationID)
  }
}
