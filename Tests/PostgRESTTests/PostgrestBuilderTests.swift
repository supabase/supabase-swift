//
//  PostgrestBuilderTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 20/08/24.
//

import ConcurrencyExtras
import Foundation
import HTTPTypes
import Helpers
import Mocker
import TestHelpers
import Testing

@testable import PostgREST

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

extension PostgrestMockerTests {
  struct PostgrestBuilderTests {
    let fixture = PostgrestQueryFixture()
    var url: URL { fixture.url }
    var sut: PostgrestClient { fixture.sut }

    @Test
    func customHeaderOnAPerCallBasis() throws {
      let url = URL(string: "http://localhost:54321/rest/v1")!
      let postgrest1 = PostgrestClient(url: url, headers: ["apikey": "foo"], logger: nil)
      let postgrest2 = try postgrest1.rpc("void_func").setHeader(
        name: .init("apikey")!, value: "bar")

      // Original client object isn't affected
      #expect(
        postgrest1.from("users").select().mutableState.request.headers[.init("apikey")!] == "foo")
      // Derived client object uses new header value
      #expect(postgrest2.mutableState.request.headers[.init("apikey")!] == "bar")
    }

    @Test
    func executeWithNonSuccessStatusCode() async throws {
      Mock(
        url: url.appendingPathComponent("users"),
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
        #expect(error.message == "Bad Request")
      }
    }

    @Test
    func executeWithNonJSONError() async throws {
      Mock(
        url: url.appendingPathComponent("users"),
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
        #expect(error.data == Data("Bad Request".utf8))
        #expect(error.response.statusCode == 400)
      }
    }

    @Test
    func maybeSingleReturnsNilOnZeroRows() async throws {
      Mock(
        url: url.appendingPathComponent("users"),
        ignoreQuery: true,
        statusCode: 406,
        data: [
          .get: Data(
            """
            {
              "code": "PGRST116",
              "message": "JSON object requested, multiple (or no) rows returned"
            }
            """.utf8
          )
        ]
      )
      .register()

      let user: User? =
        try await sut
        .from("users")
        .select()
        .maybeSingle()
        .execute()
        .value

      #expect(user == nil)
    }

    @Test
    func maybeSingleReturnsValueOnSingleRow() async throws {
      Mock(
        url: url.appendingPathComponent("users"),
        ignoreQuery: true,
        statusCode: 200,
        data: [
          .get: Data(
            """
            {
              "id": 1,
              "username": "admin"
            }
            """.utf8
          )
        ]
      )
      .register()

      let user: User? =
        try await sut
        .from("users")
        .select()
        .maybeSingle()
        .execute()
        .value

      #expect(user?.id == 1)
      #expect(user?.username == "admin")
    }

    @Test
    func executeWithHead() async throws {
      Mock(
        url: url.appendingPathComponent("users"),
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

    @Test
    func executeWithCount() async throws {
      Mock(
        url: url.appendingPathComponent("users"),
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

    @Test
    func executeWithCustomSchema() async throws {
      Mock(
        url: url.appendingPathComponent("users"),
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

    @Test
    func executeWithCustomSchemaAndHeadMethod() async throws {
      Mock(
        url: url.appendingPathComponent("users"),
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

    @Test
    func executeWithCustomSchemaAndPostMethod() async throws {
      Mock(
        url: url.appendingPathComponent("users"),
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

    @Test
    func setHeader() {
      let query = sut.from("users")
        .setHeader(name: "key", value: "value")

      #expect(query.mutableState.request.headers[.init("key")!] == "value")
    }

    // MARK: - Retry tests

    @Test
    func retryOn520ForGETRequest() async throws {
      struct MutableState {
        var callCount = 0
        var capturedHeaders = [[String: String]]()
      }

      let state = LockIsolated(MutableState())

      let sut = makeSUTWithCustomFetch { request in
        state.withValue { state in
          state.callCount += 1
          state.capturedHeaders.append(
            Dictionary(uniqueKeysWithValues: (request.allHTTPHeaderFields ?? [:]).map { $0 }))

          if state.callCount < 3 {
            return (Data(), self.makeHTTPURLResponse(statusCode: 520))
          }
          return (Data("[]".utf8), self.makeHTTPURLResponse(statusCode: 200))
        }
      }

      let result: PostgrestResponse<[User]> = try await sut.from("users").select().execute()

      state.withValue { state in
        #expect(state.callCount == 3)
        #expect(state.capturedHeaders[0]["X-Retry-Count"] == nil)
        #expect(state.capturedHeaders[1]["X-Retry-Count"] == "1")
        #expect(state.capturedHeaders[2]["X-Retry-Count"] == "2")
      }
      #expect(result.value.isEmpty)
    }

    @Test
    func retryAfterSchemaChangeUsesInjectedClock() async throws {
      let callCount = LockIsolated(0)

      let sut = makeSUTWithCustomFetch { _ in
        callCount.withValue { $0 += 1 }
        if callCount.value < 3 {
          return (Data(), self.makeHTTPURLResponse(statusCode: 520))
        }
        return (Data("[]".utf8), self.makeHTTPURLResponse(statusCode: 200))
      }

      let clock = ContinuousClock()
      let start = clock.now
      let result: PostgrestResponse<[User]> =
        try await sut
        .schema("private")
        .from("users")
        .select()
        .execute()
      let elapsed = clock.now - start

      #expect(callCount.value == 3)
      #expect(result.value.isEmpty)
      #expect(
        elapsed < .seconds(1),
        "schema(_:) must propagate the injected clock instead of falling back to the real one")
    }

    @Test
    func retryOn520ForHEADRequest() async throws {
      let callCount = LockIsolated(0)

      let sut = makeSUTWithCustomFetch { _ in
        callCount.withValue { $0 += 1 }
        if callCount.value < 2 {
          return (Data(), self.makeHTTPURLResponse(statusCode: 520))
        }
        return (Data(), self.makeHTTPURLResponse(statusCode: 200))
      }

      try await sut.from("users").select().execute(options: FetchOptions(head: true))
      #expect(callCount.value == 2)
    }

    @Test
    func noRetryOn520ForPOSTRequest() async throws {
      let callCount = LockIsolated(0)

      let sut = makeSUTWithCustomFetch { _ in
        callCount.withValue { $0 += 1 }
        return (Data(), self.makeHTTPURLResponse(statusCode: 520))
      }

      do {
        try await sut.from("users").insert(["username": "test"]).execute()
        Issue.record("Expected error to be thrown")
      } catch {
        #expect(callCount.value == 1)
      }
    }

    @Test
    func noRetryOnNon520ErrorForGET() async throws {
      let callCount = LockIsolated(0)

      let sut = makeSUTWithCustomFetch { _ in
        callCount.withValue { $0 += 1 }
        return (
          Data(#"{"message":"Bad Request"}"#.utf8),
          self.makeHTTPURLResponse(statusCode: 400)
        )
      }

      do {
        try await sut.from("users").select().execute()
        Issue.record("Expected error to be thrown")
      } catch let error as PostgrestError {
        #expect(callCount.value == 1)
        #expect(error.message == "Bad Request")
      }
    }

    @Test
    func retryOn503ForGETRequest() async throws {
      let callCount = LockIsolated(0)

      let sut = makeSUTWithCustomFetch { _ in
        callCount.withValue { $0 += 1 }
        if callCount.value < 2 {
          return (Data(), self.makeHTTPURLResponse(statusCode: 503))
        }
        return (Data("[]".utf8), self.makeHTTPURLResponse(statusCode: 200))
      }

      let result: PostgrestResponse<[User]> = try await sut.from("users").select().execute()
      #expect(callCount.value == 2)
      #expect(result.value.isEmpty)
    }

    @Test
    func retryOn503ForHEADRequest() async throws {
      let callCount = LockIsolated(0)

      let sut = makeSUTWithCustomFetch { _ in
        callCount.withValue { $0 += 1 }
        if callCount.value < 2 {
          return (Data(), self.makeHTTPURLResponse(statusCode: 503))
        }
        return (Data(), self.makeHTTPURLResponse(statusCode: 200))
      }

      try await sut.from("users").select().execute(options: FetchOptions(head: true))
      #expect(callCount.value == 2)
    }

    @Test
    func retryOnNetworkErrorForGET() async throws {
      let callCount = LockIsolated(0)

      let sut = makeSUTWithCustomFetch { _ in
        callCount.withValue { $0 += 1 }
        if callCount.value < 2 {
          throw URLError(.networkConnectionLost)
        }
        return (Data("[]".utf8), self.makeHTTPURLResponse(statusCode: 200))
      }

      let result: PostgrestResponse<[User]> = try await sut.from("users").select().execute()
      #expect(callCount.value == 2)
      #expect(result.value.isEmpty)
    }

    @Test
    func noRetryOnNetworkErrorForPOST() async throws {
      let callCount = LockIsolated(0)

      let sut = makeSUTWithCustomFetch { _ in
        callCount.withValue { $0 += 1 }
        throw URLError(.networkConnectionLost)
      }

      do {
        try await sut.from("users").insert(["username": "test"]).execute()
        Issue.record("Expected error to be thrown")
      } catch {
        #expect(callCount.value == 1)
      }
    }

    @Test
    func exhaustAllRetries() async throws {
      let callCount = LockIsolated(0)

      let sut = makeSUTWithCustomFetch { _ in
        callCount.withValue { $0 += 1 }
        return (Data(), self.makeHTTPURLResponse(statusCode: 520))
      }

      do {
        try await sut.from("users").select().execute()
        Issue.record("Expected error to be thrown")
      } catch {
        #expect(callCount.value == 4)  // 1 initial + 3 retries
      }
    }

    @Test
    func perRequestRetryDisabled() async throws {
      let callCount = LockIsolated(0)

      let sut = makeSUTWithCustomFetch { _ in
        callCount.withValue { $0 += 1 }
        return (Data(), self.makeHTTPURLResponse(statusCode: 520))
      }

      do {
        try await sut.from("users").select().retry(enabled: false).execute()
        Issue.record("Expected error to be thrown")
      } catch {
        #expect(callCount.value == 1)
      }
    }

    @Test
    func clientLevelRetryDisabled() async throws {
      let callCount = LockIsolated(0)

      let sut = makeSUTWithCustomFetch(retryEnabled: false) { _ in
        callCount.withValue { $0 += 1 }
        return (Data(), self.makeHTTPURLResponse(statusCode: 520))
      }

      do {
        try await sut.from("users").select().execute()
        Issue.record("Expected error to be thrown")
      } catch {
        #expect(callCount.value == 1)
      }
    }

    @Test
    func retryEnabledPerRequestOverridesClientDisabled() async throws {
      let callCount = LockIsolated(0)

      let sut = makeSUTWithCustomFetch(retryEnabled: false) { _ in
        callCount.withValue { $0 += 1 }
        if callCount.value < 2 {
          return (Data(), self.makeHTTPURLResponse(statusCode: 520))
        }
        return (Data("[]".utf8), self.makeHTTPURLResponse(statusCode: 200))
      }

      let result: PostgrestResponse<[User]> = try await sut.from("users").select().retry(
        enabled: true
      )
      .execute()
      #expect(callCount.value == 2)
      #expect(result.value.isEmpty)
    }

    // MARK: - Helpers

    private func makeSUTWithCustomFetch(
      retryEnabled: Bool = true,
      fetch: @escaping PostgrestClient.FetchHandler
    ) -> PostgrestClient {
      PostgrestClient(
        configuration: .init(url: url, fetch: fetch, retryEnabled: retryEnabled),
        clock: ImmediateRetryTestClock()
      )
    }

    private func makeHTTPURLResponse(statusCode: Int) -> HTTPURLResponse {
      HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
    }
  }
}

/// A no-op clock for tests — skips all sleep delays so retry tests run instantly.
struct ImmediateRetryTestClock: Clock {
  var now: ContinuousClock.Instant { ContinuousClock().now }
  var minimumResolution: ContinuousClock.Instant.Duration { ContinuousClock().minimumResolution }

  func sleep(until deadline: ContinuousClock.Instant, tolerance: Duration?) async throws {}
}
