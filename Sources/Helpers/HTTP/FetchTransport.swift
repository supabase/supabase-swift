//
//  FetchTransport.swift
//  Helpers
//
//  Created by Guilherme Souza on 09/09/26.
//

package import Foundation
package import HTTPTypes
import HTTPTypesFoundation

#if canImport(FoundationNetworking)
  package import FoundationNetworking
#endif

/// Bridges a legacy `(URLRequest) -> (Data, URLResponse)` closure to ``ClientTransport``.
/// Temporary: removed once every module exposes `transport:` directly (Task 9).
package struct FetchTransport: ClientTransport {
  let fetch: @Sendable (URLRequest) async throws -> (Data, URLResponse)

  package init(fetch: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)) {
    self.fetch = fetch
  }

  package func send(_ request: HTTPTypes.HTTPRequest, body: HTTPBody?) async throws -> (
    HTTPTypes.HTTPResponse, HTTPBody?
  ) {
    guard var urlRequest = URLRequest(httpRequest: request) else { throw URLError(.badURL) }
    if let timeout = RequestTimeout.current { urlRequest.timeoutInterval = timeout }
    if let body { urlRequest.httpBody = try await Data(collecting: body, upTo: .max) }
    let (data, response) = try await fetch(urlRequest)
    guard let head = (response as? HTTPURLResponse)?.httpResponse else {
      throw URLError(.badServerResponse)
    }
    return (head, data.isEmpty ? nil : HTTPBody(data))
  }
}
