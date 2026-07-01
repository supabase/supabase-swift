//
//  RelayErrorMiddlewareTests.swift
//  Functions
//
//  Created by Guilherme Souza on 30/06/26.
//

import HTTPTypes
import OpenAPIRuntime
import Testing

@testable import Functions

@Suite struct RelayErrorMiddlewareTests {
  let middleware = RelayErrorMiddleware()

  @Test func throwsRelayErrorOnGenuine200() async throws {
    var response = HTTPResponse(status: .ok)
    response.headerFields[HTTPField.Name("x-relay-error")!] = "true"

    await #expect(throws: FunctionsError.relayError) {
      try await middleware.intercept(
        HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/"),
        body: nil,
        baseURL: URL(string: "https://example.com")!,
        operationID: "test",
        next: { _, _, _ in (response, nil) }
      )
    }
  }

  @Test func passesCleanResponseThrough() async throws {
    let response = HTTPResponse(status: .ok)

    let (result, _) = try await middleware.intercept(
      HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/"),
      body: nil,
      baseURL: URL(string: "https://example.com")!,
      operationID: "test",
      next: { _, _, _ in (response, nil) }
    )

    #expect(result.status == .ok)
  }

  @Test func throwsRelayErrorOnNon200() async throws {
    var response = HTTPResponse(status: .badRequest)
    response.headerFields[HTTPField.Name("x-relay-error")!] = "true"

    await #expect(throws: FunctionsError.relayError) {
      try await middleware.intercept(
        HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/"),
        body: nil,
        baseURL: URL(string: "https://example.com")!,
        operationID: "test",
        next: { _, _, _ in (response, nil) }
      )
    }
  }
}
