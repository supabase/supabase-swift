//
//  HTTPClient.swift
//
//
//  Created by Guilherme Souza on 30/04/24.
//

import Foundation
import HTTPTypes

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

package protocol HTTPClientType: Sendable {
  func send(for request: HTTPRequest, from bodyData: Data?) async throws -> (Data, HTTPResponse)
}

package actor HTTPClient: HTTPClientType {
  let fetch: @Sendable (HTTPRequest, Data?) async throws -> (Data, HTTPResponse)
  let interceptors: [any HTTPClientInterceptor]

  package init(
    fetch: @escaping @Sendable (HTTPRequest, Data?) async throws -> (Data, HTTPResponse),
    interceptors: [any HTTPClientInterceptor]
  ) {
    self.fetch = fetch
    self.interceptors = interceptors
  }

  package func send(
    for request: HTTPRequest,
    from bodyData: Data?
  ) async throws -> (Data, HTTPResponse) {
    var next: @Sendable (HTTPRequest, Data?) async throws -> (Data, HTTPResponse) = { _request, _bodyData in
      var _request = _request
      if _bodyData != nil, _request.headerFields[.contentType] == nil {
        _request.headerFields[.contentType] = "application/json"
      }
      return try await self.fetch(_request, _bodyData)
    }

    for interceptor in interceptors.reversed() {
      let tmp = next
      next = {
        try await interceptor.intercept(for: $0, from: $1, next: tmp)
      }
    }

    return try await next(request, bodyData)
  }
}

package protocol HTTPClientInterceptor: Sendable {
  func intercept(
    for request: HTTPRequest,
    from bodyData: Data?,
    next: @Sendable (HTTPRequest, Data?) async throws -> (Data, HTTPResponse)
  ) async throws -> (Data, HTTPResponse)
}
