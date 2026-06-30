//
//  MockTransport.swift
//  StorageTests
//
//  Created by Guilherme Souza on 30/06/25.
//

import Foundation
import HTTPTypes
@_spi(Generated) import OpenAPIRuntime

struct MockTransport: ClientTransport, Sendable {
  let responseData: Data
  let statusCode: Int

  func send(
    _ request: HTTPRequest,
    body: HTTPBody?,
    baseURL: URL,
    operationID: String
  ) async throws -> (HTTPResponse, HTTPBody?) {
    let response = HTTPResponse(status: .init(code: statusCode))
    let responseBody: HTTPBody? = responseData.isEmpty ? nil : HTTPBody(responseData)
    return (response, responseBody)
  }
}
