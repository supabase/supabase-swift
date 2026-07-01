//
//  MockTransport.swift
//  FunctionsTests
//
//  Created by Guilherme Souza on 30/06/25.
//

import Foundation
import HTTPTypes
import OpenAPIRuntime

struct MockTransport: ClientTransport, Sendable {
  let responseData: Data
  let statusCode: Int
  var responseHeaders: HTTPFields = [:]

  func send(
    _ request: HTTPRequest,
    body: HTTPBody?,
    baseURL: URL,
    operationID: String
  ) async throws -> (HTTPResponse, HTTPBody?) {
    var response = HTTPResponse(status: .init(code: statusCode))
    for field in responseHeaders {
      response.headerFields.append(field)
    }
    let responseBody: HTTPBody? = responseData.isEmpty ? nil : HTTPBody(responseData)
    return (response, responseBody)
  }
}
