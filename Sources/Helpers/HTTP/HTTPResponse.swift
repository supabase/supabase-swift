//
//  HTTPResponse.swift
//
//
//  Created by Guilherme Souza on 30/04/24.
//

package import Foundation
package import HTTPTypes
import HTTPTypesFoundation

#if canImport(FoundationNetworking)
  package import FoundationNetworking
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
  /// Builds the buffered response from an `HTTPTypes` head. `underlyingResponse` is rebuilt
  /// so public error types keep carrying an `HTTPURLResponse`.
  package init(data: Data, head: HTTPTypes.HTTPResponse, url: URL) throws {
    guard let underlying = HTTPURLResponse(httpResponse: head, url: url) else {
      throw URLError(.badServerResponse)
    }
    self.init(data: data, response: underlying)
  }
}
