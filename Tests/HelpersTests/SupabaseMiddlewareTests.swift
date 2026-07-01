//
//  SupabaseMiddlewareTests.swift
//  HelpersTests
//

import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing
@testable import Helpers

@Suite("SupabaseMiddleware")
struct SupabaseMiddlewareTests {
  // A simple next handler that echoes back a fixed response and captures the forwarded request.
  actor RequestCapture {
    var last: HTTPTypes.HTTPRequest?
    func capture(_ request: HTTPTypes.HTTPRequest) { last = request }
  }

  private func makeNext(
    capture: RequestCapture? = nil,
    status: Int = 200,
    responseHeaders: [(String, String)] = []
  ) -> @Sendable (HTTPTypes.HTTPRequest, HTTPBody?, URL) async throws -> (
    HTTPTypes.HTTPResponse, HTTPBody?
  ) {
    return { request, _, _ in
      await capture?.capture(request)
      var fields = HTTPFields()
      for (name, value) in responseHeaders {
        fields[HTTPField.Name(name)!] = value
      }
      return (HTTPTypes.HTTPResponse(status: .init(code: status), headerFields: fields), nil)
    }
  }

  @Test("injects static headers into request")
  func injectsStaticHeaders() async throws {
    let middleware = SupabaseMiddleware(headers: ["apikey": "my-key", "X-Client-Info": "sdk/1"])
    let capture = RequestCapture()
    let next = makeNext(capture: capture)
    _ = try await middleware.intercept(
      HTTPTypes.HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/"),
      body: nil, baseURL: URL(string: "https://example.com")!,
      operationID: "op", next: next
    )
    let forwarded = await capture.last
    #expect(forwarded?.headerFields[HTTPField.Name("apikey")!] == "my-key")
    #expect(forwarded?.headerFields[HTTPField.Name("X-Client-Info")!] == "sdk/1")
  }

  @Test("does not overwrite existing header")
  func doesNotOverwriteExistingHeader() async throws {
    let middleware = SupabaseMiddleware(headers: ["apikey": "middleware-key"])
    let capture = RequestCapture()
    let next = makeNext(capture: capture)
    var request = HTTPTypes.HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/")
    request.headerFields[HTTPField.Name("apikey")!] = "caller-key"
    _ = try await middleware.intercept(
      request, body: nil, baseURL: URL(string: "https://example.com")!,
      operationID: "op", next: next
    )
    let forwarded = await capture.last
    #expect(forwarded?.headerFields[HTTPField.Name("apikey")!] == "caller-key")
  }

  @Test("injects Bearer token from tokenProvider")
  func injectsBearerToken() async throws {
    let middleware = SupabaseMiddleware(headers: [:], tokenProvider: { "test-token" })
    let capture = RequestCapture()
    let next = makeNext(capture: capture)
    _ = try await middleware.intercept(
      HTTPTypes.HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/"),
      body: nil, baseURL: URL(string: "https://example.com")!,
      operationID: "op", next: next
    )
    let forwarded = await capture.last
    #expect(forwarded?.headerFields[.authorization] == "Bearer test-token")
  }

  @Test("does not overwrite existing Authorization header")
  func doesNotOverwriteExistingAuthorization() async throws {
    let middleware = SupabaseMiddleware(headers: [:], tokenProvider: { "new-token" })
    let capture = RequestCapture()
    let next = makeNext(capture: capture)
    var request = HTTPTypes.HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/")
    request.headerFields[.authorization] = "Bearer existing-token"
    _ = try await middleware.intercept(
      request, body: nil, baseURL: URL(string: "https://example.com")!,
      operationID: "op", next: next
    )
    let forwarded = await capture.last
    #expect(forwarded?.headerFields[.authorization] == "Bearer existing-token")
  }

  @Test("no Authorization injected when tokenProvider is nil")
  func noAuthHeaderWhenNoProvider() async throws {
    let middleware = SupabaseMiddleware(headers: [:], tokenProvider: nil)
    let capture = RequestCapture()
    let next = makeNext(capture: capture)
    _ = try await middleware.intercept(
      HTTPTypes.HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/"),
      body: nil, baseURL: URL(string: "https://example.com")!,
      operationID: "op", next: next
    )
    let forwarded = await capture.last
    #expect(forwarded?.headerFields[.authorization] == nil)
  }
}
