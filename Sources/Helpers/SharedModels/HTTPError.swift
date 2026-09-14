//
//  HTTPError.swift
//
//
//  Created by Guilherme Souza on 07/05/24.
//

public import Foundation
public import HTTPTypes

/// A generic error from a HTTP request.
///
/// Contains both the response body as `Data` and the `HTTPResponse` head (status and header
/// fields) which you can use to extract more information about it.
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
    var message = "Status Code: \(response.status.code)"
    if let body = String(data: data, encoding: .utf8) {
      message += " Body: \(body)"
    }
    return message
  }
}
