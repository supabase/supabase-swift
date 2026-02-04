//
//  HTTPResponse.swift
//
//
//  Created by Guilherme Souza on 30/04/24.
//

import Foundation
import HTTPTypes

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

package struct HTTPResponse: Sendable {
  package let data: Data
  package let headers: HTTPFields
  package let statusCode: Int

  package let underlyingResponse: HTTPURLResponse

  package init(data: Data, response: HTTPURLResponse) {
    self.data = data
    headers = HTTPFields(response.allHeaderFields as? [String: String] ?? [:])
    statusCode = response.statusCode
    underlyingResponse = response
  }
}

extension HTTPResponse {
  package func decoded<T: Decodable>(as _: T.Type = T.self, decoder: JSONDecoder = JSONDecoder())
    throws -> T
  {
    try decoder.decode(T.self, from: data)
  }
}

extension HTTPResponse {
  /// A streaming HTTP response that provides both the initial response metadata
  /// and an async stream of data chunks.
  package struct Stream: Sendable {
    /// The HTTP status code from the initial response.
    package let statusCode: Int

    /// The HTTP headers from the initial response.
    package let headers: HTTPFields

    /// The underlying HTTPURLResponse.
    package let underlyingResponse: HTTPURLResponse

    /// An async stream of data chunks from the response body.
    package let body: AsyncThrowingStream<Data, any Error>

    package init(
      statusCode: Int,
      headers: HTTPFields,
      underlyingResponse: HTTPURLResponse,
      body: AsyncThrowingStream<Data, any Error>
    ) {
      self.statusCode = statusCode
      self.headers = headers
      self.underlyingResponse = underlyingResponse
      self.body = body
    }
  }
}
