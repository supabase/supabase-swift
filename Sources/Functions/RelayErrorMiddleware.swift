//
//  RelayErrorMiddleware.swift
//  Functions
//
//  Created by Guilherme Souza on 30/06/26.
//

import Foundation
import HTTPTypes
import OpenAPIRuntime

struct RelayErrorMiddleware: ClientMiddleware, Sendable {
  func intercept(
    _ request: HTTPTypes.HTTPRequest,
    body: OpenAPIRuntime.HTTPBody?,
    baseURL: URL,
    operationID: String,
    next:
      @Sendable (HTTPTypes.HTTPRequest, OpenAPIRuntime.HTTPBody?, URL) async throws -> (
        HTTPTypes.HTTPResponse, OpenAPIRuntime.HTTPBody?
      )
  ) async throws -> (HTTPTypes.HTTPResponse, OpenAPIRuntime.HTTPBody?) {
    let (response, responseBody) = try await next(request, body, baseURL)
    if let fieldName = HTTPField.Name("x-relay-error"),
      response.headerFields[fieldName] == "true"
    {
      throw FunctionsError.relayError
    }
    return (response, responseBody)
  }
}
