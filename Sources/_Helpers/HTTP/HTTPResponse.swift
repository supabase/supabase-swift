//
//  HTTPResponse.swift
//
//
//  Created by Guilherme Souza on 30/04/24.
//

import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

package struct HTTPResponse: Sendable {
  package let data: Data
  package let headers: HTTPHeaders
  package let statusCode: Int

  package let underlyingResponse: HTTPURLResponse

  package init(data: Data, response: HTTPURLResponse) {
    self.data = data
    headers = HTTPHeaders(response.allHeaderFields as? [String: String] ?? [:])
    statusCode = response.statusCode
    underlyingResponse = response
  }
}

extension HTTPResponse {
  package func decoded<T: Decodable>(as _: T.Type = T.self, decoder: JSONDecoder = JSONDecoder()) throws -> T {
    try decoder.decode(T.self, from: data)
  }
}
