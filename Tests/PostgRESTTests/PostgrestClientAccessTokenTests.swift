//
//  PostgrestClientAccessTokenTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 19/08/26.
//

import ConcurrencyExtras
import Foundation
import TestHelpers
import Testing

@testable import PostgREST

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite
struct PostgrestClientAccessTokenTests {
  let url = URL(string: "http://localhost:54321/rest/v1")!

  private func okResponse() -> (HTTPTypes.HTTPResponse, HTTPBody?) {
    (HTTPTypes.HTTPResponse(status: .ok), HTTPBody(Data("[]".utf8)))
  }

  @Test
  func accessTokenSetsAuthorizationHeader() async throws {
    let capturedHeaders = LockIsolated(HTTPFields())

    let sut = PostgrestClient(
      url: url,
      transport: ClosureTransport { request, _ in
        capturedHeaders.setValue(request.headerFields)
        return self.okResponse()
      },
      accessToken: { "access.token" }
    )

    try await sut.from("todos").select().execute()

    #expect(capturedHeaders.value[.authorization] == "Bearer access.token")
  }

  @Test
  func accessTokenIsResolvedPerRequest() async throws {
    let token = LockIsolated("first.token")
    let capturedAuthorizationHeaders = LockIsolated([String]())

    let sut = PostgrestClient(
      url: url,
      transport: ClosureTransport { request, _ in
        capturedAuthorizationHeaders.withValue {
          $0.append(request.headerFields[.authorization] ?? "")
        }
        return self.okResponse()
      },
      accessToken: { token.value }
    )

    try await sut.from("todos").select().execute()
    token.withValue { $0 = "second.token" }
    try await sut.from("todos").select().execute()

    #expect(capturedAuthorizationHeaders.value == ["Bearer first.token", "Bearer second.token"])
  }

  @Test
  func explicitAuthorizationHeaderOverridesAccessToken() async throws {
    let capturedHeaders = LockIsolated(HTTPFields())

    let sut = PostgrestClient(
      url: url,
      transport: ClosureTransport { request, _ in
        capturedHeaders.setValue(request.headerFields)
        return self.okResponse()
      },
      accessToken: { "access.token" }
    )

    try await sut.from("todos")
      .select()
      .setHeader(name: "Authorization", value: "Bearer explicit")
      .execute()

    #expect(capturedHeaders.value[.authorization] == "Bearer explicit")
  }

  @Test
  func accessTokenErrorPropagatesToExecute() async throws {
    struct TokenError: Error, Equatable {}

    let sut = PostgrestClient(
      url: url,
      transport: ClosureTransport { request, _ in
        Issue.record("transport should not be called when the access token provider throws")
        return self.okResponse()
      },
      accessToken: { throw TokenError() }
    )

    await #expect(throws: TokenError.self) {
      try await sut.from("todos").select().execute()
    }
  }

  @Test
  func noAccessTokenSendsNoAuthorizationHeader() async throws {
    let capturedHeaders = LockIsolated(HTTPFields())

    let sut = PostgrestClient(
      url: url,
      transport: ClosureTransport { request, _ in
        capturedHeaders.setValue(request.headerFields)
        return self.okResponse()
      }
    )

    try await sut.from("todos").select().execute()

    #expect(capturedHeaders.value[.authorization] == nil)
  }
}
