//
//  HTTPError.swift
//
//
//  Created by Guilherme Souza on 07/05/24.
//

import Foundation
import HTTPTypes

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// A generic error from a HTTP request.
///
/// Contains both the `Data` and `HTTPResponse` which you can use to extract more information about it.
public struct HTTPError: Error, Sendable {
  public let data: Data
  public let response: HTTPResponse

  public init(data: Data, response: HTTPResponse) {
    self.data = data
    self.response = response
  }
}

extension HTTPError: LocalizedError {
  public var errorDescription: String? {
    return "Status Code: \(response.status.code) Body: \(String(decoding: data, as: UTF8.self))"
  }
}
