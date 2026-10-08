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
      http: .init(
        transport: ClosureTransport { request, _ in
          capturedHeaders.setValue(request.headerFields)
          return self.okResponse()
        }),
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
      http: .init(
        transport: ClosureTransport { request, _ in
          capturedAuthorizationHeaders.withValue {
            $0.append(request.headerFields[.authorization] ?? "")
          }
          return self.okResponse()
        }),
      accessToken: { token.value }
    )

    try await sut.from("todos").select().execute()
    token.withValue { $0 = "second.token" }
    try await sut.from("todos").select().execute()

    #expect(capturedAuthorizationHeaders.value == ["Bearer first.token", "Bearer second.token"])
  }

  @Test
  func inFlightRequestKeepsItsResolvedTokenAcrossALaterTokenMutation() async throws {
    let token = LockIsolated("first.token")
    let capturedAuthorizationHeaders = LockIsolated([String]())
    let firstRequestIsInFlight = LockIsolated(false)
    let firstRequestMayFinish = LockIsolated(false)

    let sut = PostgrestClient(
      url: url,
      http: .init(
        transport: ClosureTransport { request, _ in
          capturedAuthorizationHeaders.withValue {
            $0.append(request.headerFields[.authorization] ?? "")
          }
          // Only the first request to reach the transport blocks here, holding it "in flight"
          // while the token mutates and a second request runs to completion around it. The
          // second request's own call recognizes `firstRequestIsInFlight` already flipped and
          // returns immediately instead of blocking a second time.
          if !firstRequestIsInFlight.value {
            firstRequestIsInFlight.setValue(true)
            await waitUntil { firstRequestMayFinish.value }
          }
          return self.okResponse()
        }),
      accessToken: { token.value }
    )

    async let first: Void = {
      _ = try await sut.from("todos").select().execute()
    }()

    await waitUntil { firstRequestIsInFlight.value }
    // The first request already resolved and fixed its token into its own request before
    // reaching the transport above, so this mutation must not reach it.
    token.setValue("second.token")

    _ = try await sut.from("todos").select().execute()
    firstRequestMayFinish.setValue(true)
    try await first

    #expect(
      capturedAuthorizationHeaders.value == ["Bearer first.token", "Bearer second.token"]
    )
  }

  @Test
  func explicitAuthorizationHeaderOverridesAccessToken() async throws {
    let capturedHeaders = LockIsolated(HTTPFields())

    let sut = PostgrestClient(
      url: url,
      http: .init(
        transport: ClosureTransport { request, _ in
          capturedHeaders.setValue(request.headerFields)
          return self.okResponse()
        }),
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
      http: .init(
        transport: ClosureTransport { _, _ in
          Issue.record("transport should not be called when the access token provider throws")
          return self.okResponse()
        }),
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
      http: .init(
        transport: ClosureTransport { request, _ in
          capturedHeaders.setValue(request.headerFields)
          return self.okResponse()
        }))

    try await sut.from("todos").select().execute()

    #expect(capturedHeaders.value[.authorization] == nil)
  }
}
