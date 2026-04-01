//
//  PostgrestBuilderTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 20/08/24.
//

import ConcurrencyExtras
import Helpers
import InlineSnapshotTesting
import Mocker
import XCTest

@testable import PostgREST

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

final class PostgrestBuilderTests: PostgrestQueryTests {
  func testCustomHeaderOnAPerCallBasis() throws {
    let url = URL(string: "http://localhost:54321/rest/v1")!
    let postgrest1 = PostgrestClient(
      url: url,
      headers: ["apikey": "foo"],
      logger: nil
    )
    let postgrest2 = try postgrest1.rpc("void_func").setHeader(
      name: .init("apikey")!,
      value: "bar"
    )

    // Original client object isn't affected
    XCTAssertEqual(
      postgrest1.from("users").select().mutableState.request.headers[
        .init("apikey")!
      ],
      "foo"
    )
    // Derived client object uses new header value
    XCTAssertEqual(
      postgrest2.mutableState.request.headers[.init("apikey")!],
      "bar"
    )
  }

  func testExecuteWithNonSuccessStatusCode() async throws {
    Mock(
      url: Self.url.appendingPathComponent("users"),
      ignoreQuery: true,
      statusCode: 400,
      data: [
        .get: Data(
          """
          {
            "message": "Bad Request"
          }
          """.utf8
        )
      ]
    )
    .register()

    do {
      try await sut
        .from("users")
        .select()
        .execute()
    } catch let error as PostgrestError {
      XCTAssertEqual(error.message, "Bad Request")
    }
  }

  func testExecuteWithNonJSONError() async throws {
    Mock(
      url: Self.url.appendingPathComponent("users"),
      ignoreQuery: true,
      statusCode: 400,
      data: [
        .get: Data("Bad Request".utf8)
      ]
    )
    .register()

    do {
      try await sut
        .from("users")
        .select()
        .execute()
    } catch let error as HTTPError {
      XCTAssertEqual(error.data, Data("Bad Request".utf8))
      XCTAssertEqual(error.response.statusCode, 400)
    }
  }

  func testExecuteWithHead() async throws {
    Mock(
      url: Self.url.appendingPathComponent("users"),
      ignoreQuery: true,
      statusCode: 200,
      data: [
        .head: Data()
      ]
    )
    .snapshotRequest {
      #"""
      curl \
      	--head \
      	--header "Accept: application/json" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/rest/v1/users?select=*"
      """#
    }
    .register()

    try await sut.from("users")
      .select()
      .execute(options: FetchOptions(head: true))
  }

  func testExecuteWithCount() async throws {
    Mock(
      url: Self.url.appendingPathComponent("users"),
      ignoreQuery: true,
      statusCode: 200,
      data: [
        .get: Data("[]".utf8)
      ]
    )
    .snapshotRequest {
      #"""
      curl \
      	--header "Accept: application/json" \
      	--header "Content-Type: application/json" \
      	--header "Prefer: count=exact" \
      	--header "X-Client-Info: postgrest-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/rest/v1/users?select=*"
      """#
    }
    .register()

    try await sut.from("users")
      .select()
      .execute(options: FetchOptions(count: .exact))
  }

  func testExecuteWithCustomSchema() async throws {
    Mock(
      url: Self.url.appendingPathComponent("users"),
      ignoreQuery: true,
      statusCode: 200,
      data: [
        .get: Data("[]".utf8)
      ]
    )
    .snapshotRequest {
      #"""
      curl \
      	--header "Accept: application/json" \
      	--header "Accept-Profile: private" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/rest/v1/users?select=*"
      """#
    }
    .register()

    try await sut
      .schema("private")
      .from("users")
      .select()
      .execute()
  }

  func testExecuteWithCustomSchemaAndHeadMethod() async throws {
    Mock(
      url: Self.url.appendingPathComponent("users"),
      ignoreQuery: true,
      statusCode: 200,
      data: [
        .head: Data()
      ]
    )
    .snapshotRequest {
      #"""
      curl \
      	--head \
      	--header "Accept: application/json" \
      	--header "Accept-Profile: private" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/rest/v1/users?select=*"
      """#
    }
    .register()

    try await sut
      .schema("private")
      .from("users")
      .select()
      .execute(options: FetchOptions(head: true))
  }

  func testExecuteWithCustomSchemaAndPostMethod() async throws {
    Mock(
      url: Self.url.appendingPathComponent("users"),
      ignoreQuery: true,
      statusCode: 201,
      data: [
        .post: Data()
      ]
    )
    .snapshotRequest {
      #"""
      curl \
      	--request POST \
      	--header "Accept: application/json" \
      	--header "Content-Length: 19" \
      	--header "Content-Profile: private" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"username\":\"test\"}" \
      	"http://localhost:54321/rest/v1/users"
      """#
    }
    .register()

    try await sut
      .schema("private")
      .from("users")
      .insert(["username": "test"])
      .execute()
  }

  func testSetHeader() {
    let query = sut.from("users")
      .setHeader(name: "key", value: "value")

    XCTAssertEqual(query.mutableState.request.headers[.init("key")!], "value")
  }

  // MARK: - Retry tests

  override func setUp() {
    super.setUp()
    #if DEBUG
      _clock = ImmediateRetryTestClock()
    #endif
  }

  override func tearDown() {
    super.tearDown()
    #if DEBUG
      _clock = _resolveClock()
    #endif
  }

  func testRetryOn520ForGETRequest() async throws {
    struct MutableState {
      var callCount = 0
      var capturedHeaders = [[String: String]]()
    }

    let state = LockIsolated(MutableState())

    let sut = makeSUTWithCustomFetch { request in
      state.withValue { state in
        state.callCount += 1
        state.capturedHeaders.append(
          Dictionary(
            uniqueKeysWithValues: (request.allHTTPHeaderFields ?? [:]).map {
              $0
            }
          )
        )

        if state.callCount < 3 {
          return (Data(), Self.makeHTTPURLResponse(statusCode: 520))
        }
        return (Data("[]".utf8), Self.makeHTTPURLResponse(statusCode: 200))
      }
    }

    let result: PostgrestResponse<[User]> = try await sut.from("users").select()
      .execute()

    state.withValue { state in
      XCTAssertEqual(state.callCount, 3)
      XCTAssertNil(state.capturedHeaders[0]["X-Retry-Count"])
      XCTAssertEqual(state.capturedHeaders[1]["X-Retry-Count"], "1")
      XCTAssertEqual(state.capturedHeaders[2]["X-Retry-Count"], "2")
      XCTAssertTrue(result.value.isEmpty)
    }
  }

  func testRetryOn520ForHEADRequest() async throws {
    let callCount = LockIsolated(0)

    let sut = makeSUTWithCustomFetch { _ in
      callCount.withValue { $0 += 1 }
      if callCount.value < 2 {
        return (Data(), Self.makeHTTPURLResponse(statusCode: 520))
      }
      return (Data(), Self.makeHTTPURLResponse(statusCode: 200))
    }

    try await sut.from("users").select().execute(
      options: FetchOptions(head: true)
    )
    XCTAssertEqual(callCount.value, 2)
  }

  func testNoRetryOn520ForPOSTRequest() async throws {
    let callCount = LockIsolated(0)

    let sut = makeSUTWithCustomFetch { _ in
      callCount.withValue { $0 += 1 }
      return (Data(), Self.makeHTTPURLResponse(statusCode: 520))
    }

    do {
      try await sut.from("users").insert(["username": "test"]).execute()
      XCTFail("Expected error to be thrown")
    } catch {
      XCTAssertEqual(callCount.value, 1)
    }
  }

  func testNoRetryOnNon520ErrorForGET() async throws {
    let callCount = LockIsolated(0)

    let sut = makeSUTWithCustomFetch { _ in
      callCount.withValue { $0 += 1 }
      return (
        Data(#"{"message":"Bad Request"}"#.utf8),
        Self.makeHTTPURLResponse(statusCode: 400)
      )
    }

    do {
      try await sut.from("users").select().execute()
      XCTFail("Expected error to be thrown")
    } catch let error as PostgrestError {
      XCTAssertEqual(callCount.value, 1)
      XCTAssertEqual(error.message, "Bad Request")
    }
  }

  func testRetryOn503ForGETRequest() async throws {
    let callCount = LockIsolated(0)

    let sut = makeSUTWithCustomFetch { _ in
      callCount.withValue { $0 += 1 }
      if callCount.value < 2 {
        return (Data(), self.makeHTTPURLResponse(statusCode: 503))
      }
      return (Data("[]".utf8), self.makeHTTPURLResponse(statusCode: 200))
    }

    let result: PostgrestResponse<[User]> = try await sut.from("users").select().execute()
    XCTAssertEqual(callCount.value, 2)
    XCTAssertTrue(result.value.isEmpty)
  }

  func testRetryOn503ForHEADRequest() async throws {
    let callCount = LockIsolated(0)

    let sut = makeSUTWithCustomFetch { _ in
      callCount.withValue { $0 += 1 }
      if callCount.value < 2 {
        return (Data(), self.makeHTTPURLResponse(statusCode: 503))
      }
      return (Data(), self.makeHTTPURLResponse(statusCode: 200))
    }

    try await sut.from("users").select().execute(options: FetchOptions(head: true))
    XCTAssertEqual(callCount.value, 2)
  }

  func testRetryOnNetworkErrorForGET() async throws {
    let callCount = LockIsolated(0)

    let sut = makeSUTWithCustomFetch { _ in
      callCount.withValue { $0 += 1 }
      if callCount.value < 2 {
        throw URLError(.networkConnectionLost)
      }
      return (Data("[]".utf8), Self.makeHTTPURLResponse(statusCode: 200))
    }

    let result: PostgrestResponse<[User]> = try await sut.from("users").select()
      .execute()
    XCTAssertEqual(callCount.value, 2)
    XCTAssertTrue(result.value.isEmpty)
  }

  func testNoRetryOnNetworkErrorForPOST() async throws {
    let callCount = LockIsolated(0)

    let sut = makeSUTWithCustomFetch { _ in
      callCount.withValue { $0 += 1 }
      throw URLError(.networkConnectionLost)
    }

    do {
      try await sut.from("users").insert(["username": "test"]).execute()
      XCTFail("Expected error to be thrown")
    } catch {
      XCTAssertEqual(callCount.value, 1)
    }
  }

  func testExhaustAllRetries() async throws {
    let callCount = LockIsolated(0)

    let sut = makeSUTWithCustomFetch { _ in
      callCount.withValue { $0 += 1 }
      return (Data(), Self.makeHTTPURLResponse(statusCode: 520))
    }

    do {
      try await sut.from("users").select().execute()
      XCTFail("Expected error to be thrown")
    } catch {
      XCTAssertEqual(callCount.value, 4)  // 1 initial + 3 retries
    }
  }

  func testPerRequestRetryDisabled() async throws {
    let callCount = LockIsolated(0)

    let sut = makeSUTWithCustomFetch { _ in
      callCount.withValue { $0 += 1 }
      return (Data(), Self.makeHTTPURLResponse(statusCode: 520))
    }

    do {
      try await sut.from("users").select().retry(enabled: false).execute()
      XCTFail("Expected error to be thrown")
    } catch {
      XCTAssertEqual(callCount.value, 1)
    }
  }

  func testClientLevelRetryDisabled() async throws {
    let callCount = LockIsolated(0)

    let sut = makeSUTWithCustomFetch(retryEnabled: false) { _ in
      callCount.withValue { $0 += 1 }
      return (Data(), Self.makeHTTPURLResponse(statusCode: 520))
    }

    do {
      try await sut.from("users").select().execute()
      XCTFail("Expected error to be thrown")
    } catch {
      XCTAssertEqual(callCount.value, 1)
    }
  }

  func testRetryEnabledPerRequestOverridesClientDisabled() async throws {
    let callCount = LockIsolated(0)

    let sut = makeSUTWithCustomFetch(retryEnabled: false) { _ in
      callCount.withValue { $0 += 1 }
      if callCount.value < 2 {
        return (Data(), Self.makeHTTPURLResponse(statusCode: 520))
      }
      return (Data("[]".utf8), Self.makeHTTPURLResponse(statusCode: 200))
    }

    let result: PostgrestResponse<[User]> = try await sut.from("users")
      .select()
      .retry(enabled: true)
      .execute()
    XCTAssertEqual(callCount.value, 2)
    XCTAssertTrue(result.value.isEmpty)
  }

  // MARK: - Helpers

  private func makeSUTWithCustomFetch(
    retryEnabled: Bool = true,
    fetch: @escaping PostgrestClient.FetchHandler
  ) -> PostgrestClient {
    PostgrestClient(url: Self.url, fetch: fetch, retryEnabled: retryEnabled)
  }

  private static func makeHTTPURLResponse(statusCode: Int)
    -> HTTPURLResponse
  {
    HTTPURLResponse(
      url: url,
      statusCode: statusCode,
      httpVersion: nil,
      headerFields: nil
    )!
  }
}

/// A no-op clock for tests — skips all sleep delays so retry tests run instantly.
struct ImmediateRetryTestClock: _Clock {
  func sleep(for duration: TimeInterval) async throws {}
}
