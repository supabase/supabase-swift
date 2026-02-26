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

public struct HTTPResponse: Sendable {
  public let data: Data
  public let headers: HTTPFields
  public let statusCode: Int

  public let underlyingResponse: HTTPURLResponse

  public init(data: Data, response: HTTPURLResponse) {
    self.data = data
    headers = HTTPFields(response.allHeaderFields as? [String: String] ?? [:])
    statusCode = response.statusCode
    underlyingResponse = response
  }
}

extension HTTPResponse {
  public func decoded<T: Decodable>(as _: T.Type = T.self, decoder: JSONDecoder = JSONDecoder()) throws -> T {
    try decoder.decode(T.self, from: data)
  }
}
