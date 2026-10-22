//
//  AccessTokenMiddlewareTests.swift
//  HelpersTests
//
//  Created by Guilherme Souza on 06/10/26.
//

import HTTPTypes
import Testing

@testable import Helpers

@Suite
struct AccessTokenMiddlewareTests {
  struct TokenError: Error {}

  let request = HTTPTypes.HTTPRequest(method: .get, scheme: "https", authority: "a.b", path: "/")

  func send(
    _ request: HTTPTypes.HTTPRequest,
    token: @escaping @Sendable () async throws -> String?
  ) async throws -> String? {
    try await AccessTokenMiddleware(getAccessToken: token)
      .intercept(request, body: nil) { request, _ in
        (HTTPTypes.HTTPResponse(status: .ok, headerFields: request.headerFields), nil)
      }
      .0.headerFields[.authorization]
  }

  @Test
  func setsTheBearerWhenTheRequestCarriesNoAuthorization() async throws {
    #expect(try await send(request) { "token" } == "Bearer token")
  }

  @Test
  func leavesAnExistingAuthorizationAlone() async throws {
    var request = request
    request.headerFields[.authorization] = "Bearer per-call"
    #expect(try await send(request) { "token" } == "Bearer per-call")
  }

  @Test
  func sendsNoAuthorizationForANilToken() async throws {
    #expect(try await send(request) { nil } == nil)
  }

  @Test
  func propagatesTheProviderErrorUnwrapped() async {
    await #expect(throws: TokenError.self) {
      try await send(request) { throw TokenError() }
    }
  }
}
