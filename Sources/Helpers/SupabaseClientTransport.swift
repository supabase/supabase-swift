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
/// Pure delegation to `URLSessionTransport` for correct streaming behaviour.
/// Header injection (auth, apikey, X-Client-Info) is handled by `SupabaseMiddleware`.
package struct SupabaseClientTransport: ClientTransport, Sendable {
  private let inner: URLSessionTransport

  package init(session: URLSession = URLSession(configuration: .default)) {
    self.inner = URLSessionTransport(configuration: .init(session: session))
  }

  package func send(
    _ request: HTTPTypes.HTTPRequest,
    body: HTTPBody?,
    baseURL: URL,
    operationID: String
  ) async throws -> (HTTPTypes.HTTPResponse, HTTPBody?) {
    try await inner.send(request, body: body, baseURL: baseURL, operationID: operationID)
  }
}
