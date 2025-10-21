//
//  HTTPClient.swift
//
//
//  Created by Guilherme Souza on 30/04/24.
//

import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

package protocol HTTPClientType: Sendable {
  func send(_ request: HTTPRequest) async throws -> HTTPResponse
  func stream(_ request: HTTPRequest) -> AsyncThrowingStream<Data, any Error>
}

package struct HTTPClient: HTTPClientType {
  let fetch: @Sendable (URLRequest) async throws -> (Data, URLResponse)
  let interceptors: [any HTTPClientInterceptor]

  package init(
    fetch: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse),
    interceptors: [any HTTPClientInterceptor]
  ) {
    self.fetch = fetch
    self.interceptors = interceptors
  }

  package func send(_ request: HTTPRequest) async throws -> HTTPResponse {
    var next: @Sendable (HTTPRequest) async throws -> HTTPResponse = { _request in
      let urlRequest = _request.urlRequest
      let (data, response) = try await self.fetch(urlRequest!)
      guard let httpURLResponse = response as? HTTPURLResponse else {
        throw URLError(.badServerResponse)
      }
      return HTTPResponse(data: data, response: httpURLResponse)
    }

    for interceptor in interceptors.reversed() {
      let tmp = next
      next = {
        try await interceptor.intercept($0, next: tmp)
      }
    }

    return try await next(request)
  }

  package func stream(_ request: HTTPRequest) -> AsyncThrowingStream<Data, any Error> {
    fatalError("Unsupported, please use AlamofireHTTPClient.")
  }
}

package protocol HTTPClientInterceptor: Sendable {
  func intercept(
    _ request: HTTPRequest,
    next: @Sendable (HTTPRequest) async throws -> HTTPResponse
  ) async throws -> HTTPResponse
}
