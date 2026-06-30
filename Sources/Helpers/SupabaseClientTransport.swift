//
//  SupabaseClientTransport.swift
//  Helpers
//
//  Created by Guilherme Souza on 30/06/26.
//

import Foundation
import HTTPTypes
import OpenAPIRuntime

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// URLSession-based `ClientTransport` for generated Supabase API clients.
///
/// Builds `URLRequest` values from `HTTPRequest`, injects a Bearer token via
/// `tokenProvider` when the request has no existing `Authorization` header,
/// and converts the response back to `HTTPResponse` + `HTTPBody`.
///
/// This transport is standalone — it does not depend on `_HTTPClient`.
package struct SupabaseClientTransport: ClientTransport, @unchecked Sendable {
  package let session: URLSession
  package let tokenProvider: (@Sendable () async throws -> String?)?

  package init(
    session: URLSession = URLSession(configuration: .default),
    tokenProvider: (@Sendable () async throws -> String?)? = nil
  ) {
    self.session = session
    self.tokenProvider = tokenProvider
  }

  package func send(
    _ request: HTTPTypes.HTTPRequest,
    body: HTTPBody?,
    baseURL: URL,
    operationID: String
  ) async throws -> (HTTPTypes.HTTPResponse, HTTPBody?) {
    let urlRequest = try await buildURLRequest(request, body: body, baseURL: baseURL)
    let (data, urlResponse) = try await session.data(for: urlRequest)

    guard let httpURLResponse = urlResponse as? HTTPURLResponse else {
      throw URLError(.badServerResponse)
    }

    var responseHeaderFields = HTTPFields()
    for (key, value) in httpURLResponse.allHeaderFields {
      let keyString = String(describing: key)
      let valueString = String(describing: value)
      if let fieldName = HTTPField.Name(keyString) {
        responseHeaderFields.append(HTTPField(name: fieldName, value: valueString))
      }
    }

    let httpResponse = HTTPTypes.HTTPResponse(
      status: HTTPTypes.HTTPResponse.Status(code: httpURLResponse.statusCode),
      headerFields: responseHeaderFields
    )

    let responseBody: HTTPBody? = data.isEmpty ? nil : HTTPBody(data)
    return (httpResponse, responseBody)
  }

  private func buildURLRequest(
    _ request: HTTPTypes.HTTPRequest,
    body: HTTPBody?,
    baseURL: URL
  ) async throws -> URLRequest {
    guard
      var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
      let requestPath = request.path
    else {
      throw URLError(.badURL)
    }

    // Merge the operation path into the base URL path.
    // Base: https://x.supabase.co/storage/v1  path: /bucket
    // Result: https://x.supabase.co/storage/v1/bucket
    let existingPath =
      components.path.hasSuffix("/")
      ? String(components.path.dropLast()) : components.path
    let operationPath = requestPath.hasPrefix("/") ? requestPath : "/\(requestPath)"
    components.path = existingPath + operationPath

    // Move query items from the request path into URLComponents.
    if let queryStart = operationPath.firstIndex(of: "?") {
      let queryString = String(operationPath[queryStart...].dropFirst())
      components.query = queryString
      components.path = existingPath + String(operationPath[operationPath.startIndex..<queryStart])
    }

    guard let url = components.url else {
      throw URLError(.badURL)
    }

    var urlRequest = URLRequest(url: url)
    urlRequest.httpMethod = request.method.rawValue

    // Copy request headers.
    for field in request.headerFields {
      urlRequest.setValue(field.value, forHTTPHeaderField: field.name.rawName)
    }

    // Inject auth token only when no Authorization header is present.
    if urlRequest.value(forHTTPHeaderField: "Authorization") == nil,
      let token = try await tokenProvider?()
    {
      urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    // Collect body.
    if let body {
      var data = Data()
      for try await chunk in body {
        data.append(contentsOf: chunk)
      }
      urlRequest.httpBody = data
    }

    return urlRequest
  }
}
