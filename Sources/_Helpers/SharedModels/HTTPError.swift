//
//  HTTPError.swift
//
//
//  Created by Guilherme Souza on 07/05/24.
//

import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// A generic error from a HTTP request.
///
/// Contains both the `Data` and `HTTPURLResponse` which you can use to extract more information about it.
public struct HTTPError: Error, Sendable {
  public let data: Data
  public let response: HTTPURLResponse

  public init(data: Data, response: HTTPURLResponse) {
    self.data = data
    self.response = response
  }
}

extension HTTPError: LocalizedError {
  public var errorDescription: String? {
      var message = "Status Code: \(self.response.statusCode)"
      if let body = String(data: data, encoding: .utf8) {
          message += " Body: \(body)"
      }
      return message
  }
}
