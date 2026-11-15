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

@_spi(Experimental) @testable import PostgREST

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite
struct PostgrestClientAccessTokenTests {
  struct TokenError: Error, Equatable {}

  let url = URL(string: "http://localhost:54321/rest/v1")!

  private func okResponse() -> (HTTPTypes.HTTPResponse, HTTPBody?) {
    (HTTPTypes.HTTPResponse(status: .ok), HTTPBody(Data("[]".utf8)))
  }

  private func makeSUT(
    headers: HTTPFields = [:],
    accessToken: @escaping @Sendable () async throws -> String?,
    transport:
      @escaping @Sendable (HTTPTypes.HTTPRequest, HTTPBody?) async throws -> (
        HTTPTypes.HTTPResponse, HTTPBody?
      )
  ) throws -> PostgrestClient {
    try PostgrestClient(
      configuration: .init(
        url: url,
        headers: headers,
        http: .init(
          transport: ClosureTransport(handler: transport),
          middlewares: [AccessTokenMiddleware(getAccessToken: accessToken)]),
        clock: ImmediateRetryTestClock()
      )
    )
  }

  @Test
  func accessTokenMiddlewareSetsAuthorizationHeader() async throws {
    let capturedHeaders = LockIsolated(HTTPFields())
    let sut = try makeSUT(accessToken: { "access.token" }) { request, _ in
      capturedHeaders.setValue(request.headerFields)
      return self.okResponse()
    }

    try await sut.from("todos").select().execute()

    #expect(capturedHeaders.value[.authorization] == "Bearer access.token")
  }

  @Test
  func accessTokenIsResolvedPerRequest() async throws {
    let token = LockIsolated("first.token")
    let captured = LockIsolated([String]())
    let sut = try makeSUT(accessToken: { token.value }) { request, _ in
      captured.withValue { $0.append(request.headerFields[.authorization] ?? "") }
      return self.okResponse()
    }

    try await sut.from("todos").select().execute()
    token.setValue("second.token")
    try await sut.from("todos").select().execute()

    #expect(captured.value == ["Bearer first.token", "Bearer second.token"])
  }

  @Test
  func retriedRequestGetsAFreshToken() async throws {
    let calls = LockIsolated(0)
    let captured = LockIsolated([String]())
    let sut = try makeSUT(
      accessToken: {
        calls.withValue { $0 += 1 }
        return "token-\(calls.value)"
      }
    ) { request, _ in
      captured.withValue { $0.append(request.headerFields[.authorization] ?? "") }
      return captured.value.count == 1
        ? (HTTPTypes.HTTPResponse(status: .serviceUnavailable), nil) : self.okResponse()
    }

    try await sut.from("todos").select().execute()

    #expect(captured.value == ["Bearer token-1", "Bearer token-2"])
  }

  @Test
  func perCallAuthorizationHeaderWins() async throws {
    let capturedHeaders = LockIsolated(HTTPFields())
    let sut = try makeSUT(accessToken: { throw TokenError() }) { request, _ in
      capturedHeaders.setValue(request.headerFields)
      return self.okResponse()
    }

    try await sut.from("todos")
      .select()
      .settingHeader(name: .authorization, value: "Bearer explicit")
      .execute()

    #expect(capturedHeaders.value[.authorization] == "Bearer explicit")
  }

  @Test
  func staticAuthorizationHeaderWins() async throws {
    let capturedHeaders = LockIsolated(HTTPFields())
    let sut = try makeSUT(
      headers: [.authorization: "Bearer static"], accessToken: { throw TokenError() }
    ) { request, _ in
      capturedHeaders.setValue(request.headerFields)
      return self.okResponse()
    }

    try await sut.from("todos").select().execute()

    #expect(capturedHeaders.value[.authorization] == "Bearer static")
  }

  @Test
  func accessTokenErrorFailsTheRequestAsAPostgrestError() async throws {
    let sut = try makeSUT(accessToken: { throw TokenError() }) { _, _ in
      Issue.record("transport should not be called when the access token provider throws")
      return self.okResponse()
    }

    let error = await #expect(throws: PostgrestError.self) {
      try await sut.from("todos").select().execute()
    }
    #expect(error?.kind == .accessToken)
    #expect(error?.underlyingError is TokenError)
  }

  @Test
  func accessTokenErrorFailsTheTypedQueryTheSameWay() async throws {
    struct Todo: _PostgrestRelation {
      static let relationName = "todos"
      static let selectString = "*"
      var id: Int
      struct Columns: Sendable {
        let id = _PostgrestColumn<Todo, Int>("id")
      }
      static let columns = Columns()
    }

    let sut = try makeSUT(accessToken: { throw TokenError() }) { _, _ in
      Issue.record("transport should not be called when the access token provider throws")
      return self.okResponse()
    }

    let error = await #expect(throws: PostgrestError.self) {
      try await sut.from(Todo.self).select().execute()
    }
    #expect(error?.kind == .accessToken)
    #expect(error?.underlyingError is TokenError)
  }

  @Test
  func noMiddlewareSendsNoAuthorizationHeader() async throws {
    let capturedHeaders = LockIsolated(HTTPFields())
    let sut = try PostgrestClient(
      configuration: .init(
        url: url,
        http: .init(
          transport: ClosureTransport { request, _ in
            capturedHeaders.setValue(request.headerFields)
            return self.okResponse()
          })
      )
    )

    try await sut.from("todos").select().execute()

    #expect(capturedHeaders.value[.authorization] == nil)
  }
}
