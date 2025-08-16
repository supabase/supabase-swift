import Foundation
import HTTPTypes
import HTTPTypesFoundation
import OpenAPIRuntime

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// A ClientTransport implementation that adapts the old Fetch api.
package struct FetchTransportAdapter: ClientTransport {
  let fetch: @Sendable (_ request: URLRequest) async throws -> (Data, URLResponse)

  package init(fetch: @escaping @Sendable (_ request: URLRequest) async throws -> (Data, URLResponse)) {
    self.fetch = fetch
  }

  package func send(
    _ request: HTTPTypes.HTTPRequest,
    body: HTTPBody?,
    baseURL: URL,
    operationID: String
  ) async throws -> (HTTPTypes.HTTPResponse, HTTPBody?) {
    guard var urlRequest = URLRequest(httpRequest: request) else {
      throw URLError(.badURL)
    }

    if let body {
      urlRequest.httpBody = try await Data(collecting: body, upTo: .max)
    }

    let (data, response) = try await fetch(urlRequest)

    guard let httpURLResponse = response as? HTTPURLResponse,
      let httpResponse = httpURLResponse.httpResponse
    else {
      throw URLError(.badServerResponse)
    }

    let body = HTTPBody(data)
    return (httpResponse, body)
  }
}