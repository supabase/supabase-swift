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
  func send(_ request: HTTPRequest, _ bodyData: Data?) async throws -> (Data, HTTPResponse)
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
    _ request: HTTPRequest,
    _ bodyData: Data?
  ) async throws -> (Data, HTTPResponse) {
    var next: @Sendable (HTTPRequest, Data?) async throws -> (Data, HTTPResponse) = {
      return try await self.fetch($0, $1)
    }

    for interceptor in interceptors.reversed() {
      let tmp = next
      next = {
        try await interceptor.intercept($0, $1, next: tmp)
      }
    }

    return try await next(request, bodyData)
  }
}

package protocol HTTPClientInterceptor: Sendable {
  func intercept(
    _ request: HTTPRequest,
    _ bodyData: Data?,
    next: @Sendable (HTTPRequest, Data?) async throws -> (Data, HTTPResponse)
  ) async throws -> (Data, HTTPResponse)
}

extension [URLQueryItem] {
  package mutating func appendOrUpdate(_ queryItem: URLQueryItem) {
    if let index = self.firstIndex(where: { $0.name == queryItem.name }) {
      self[index] = queryItem
    } else {
      self.append(queryItem)
    }
  }
}
