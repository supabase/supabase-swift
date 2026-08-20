//
//  PostgrestClientAccessTokenTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 19/08/26.
//

import ConcurrencyExtras
import Foundation
import Testing

@testable import PostgREST

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite
struct PostgrestClientAccessTokenTests {
  let url = URL(string: "http://localhost:54321/rest/v1")!

  private func okResponse(for request: URLRequest) -> (Data, URLResponse) {
    (
      Data("[]".utf8),
      HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
    )
  }

  @Test
  func accessTokenSetsAuthorizationHeader() async throws {
    let capturedHeaders = LockIsolated([String: String]())

    let sut = PostgrestClient(
      url: url,
      fetch: { request in
        capturedHeaders.withValue { $0 = request.allHTTPHeaderFields ?? [:] }
        return self.okResponse(for: request)
      },
      accessToken: { "access.token" }
    )

    try await sut.from("todos").select().execute()

    #expect(capturedHeaders.value["Authorization"] == "Bearer access.token")
  }

  @Test
  func accessTokenIsResolvedPerRequest() async throws {
    let token = LockIsolated("first.token")
    let capturedAuthorizationHeaders = LockIsolated([String]())

    let sut = PostgrestClient(
      url: url,
      fetch: { request in
        capturedAuthorizationHeaders.withValue {
          $0.append(request.value(forHTTPHeaderField: "Authorization") ?? "")
        }
        return self.okResponse(for: request)
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
    let capturedHeaders = LockIsolated([String: String]())

    let sut = PostgrestClient(
      url: url,
      fetch: { request in
        capturedHeaders.withValue { $0 = request.allHTTPHeaderFields ?? [:] }
        return self.okResponse(for: request)
      },
      accessToken: { "access.token" }
    )

    try await sut.from("todos")
      .select()
      .setHeader(name: "Authorization", value: "Bearer explicit")
      .execute()

    #expect(capturedHeaders.value["Authorization"] == "Bearer explicit")
  }

  @Test
  func accessTokenErrorPropagatesToExecute() async throws {
    struct TokenError: Error, Equatable {}

    let sut = PostgrestClient(
      url: url,
      fetch: { request in
        Issue.record("fetch should not be called when the access token provider throws")
        return self.okResponse(for: request)
      },
      accessToken: { throw TokenError() }
    )

    await #expect(throws: TokenError.self) {
      try await sut.from("todos").select().execute()
    }
  }

  @Test
  func noAccessTokenSendsNoAuthorizationHeader() async throws {
    let capturedHeaders = LockIsolated([String: String]())

    let sut = PostgrestClient(
      url: url,
      fetch: { request in
        capturedHeaders.withValue { $0 = request.allHTTPHeaderFields ?? [:] }
        return self.okResponse(for: request)
      }
    )

    try await sut.from("todos").select().execute()

    #expect(capturedHeaders.value["Authorization"] == nil)
  }
}
