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
  @Suite(.mockerSerialized)
  struct PostgrestBuilderTests {
    let fixture = PostgrestQueryFixture()
    var url: URL { fixture.url }
    var sut: PostgrestClient { fixture.sut }

    @Test
    func customHeaderOnAPerCallBasis() throws {
      let url = URL(string: "http://localhost:54321/rest/v1")!
      let postgrest1 = PostgrestClient(url: url, headers: ["apikey": "foo"])
      let postgrest2 = try postgrest1.rpc("void_func").setHeader(
        name: .init("apikey")!, value: "bar")

      // Original client object isn't affected
      #expect(
        postgrest1.from("users").select().request.headers[.init("apikey")!] == "foo")
      // Derived client object uses new header value
      #expect(postgrest2.request.headers[.init("apikey")!] == "bar")
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
        Issue.record("Expected error to be thrown")
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
        Issue.record("Expected error to be thrown")
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
              "details": "Results contain 0 rows, application/vnd.pgrst.object+json requires 1 row",
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
    func maybeSingleReturnsNilOnZeroRowsWithNewerPostgrestWording() async throws {
      Mock(
        url: url.appendingPathComponent("users"),
        ignoreQuery: true,
        statusCode: 406,
        data: [
          .get: Data(
            """
            {
              "code": "PGRST116",
              "details": "The result contains 0 rows",
              "message": "Cannot coerce the result to a single JSON object"
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
    func maybeSingleThrowsOnMultipleRows() async throws {
      Mock(
        url: url.appendingPathComponent("users"),
        ignoreQuery: true,
        statusCode: 406,
        data: [
          .get: Data(
            """
            {
              "code": "PGRST116",
              "details": "Results contain 2 rows, application/vnd.pgrst.object+json requires 1 row",
              "message": "JSON object requested, multiple (or no) rows returned"
            }
            """.utf8
          )
        ]
      )
      .register()

      do {
        let _: User? =
          try await sut
          .from("users")
          .select()
          .maybeSingle()
          .execute()
          .value
        Issue.record("Expected error to be thrown")
      } catch let error as PostgrestError {
        #expect(error.code == "PGRST116")
      }
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
        .select()
        .setHeader(name: "key", value: "value")

      #expect(query.request.headers[.init("key")!] == "value")
    }

    // MARK: - Encoder/decoder override tests

    @Test
    func insertPerCallEncoderOverridesClientDefault() async throws {
      let capturedBody = LockIsolated<Data?>(nil)
      let sut = makeSUTWithCustomFetch { request in
        capturedBody.setValue(request.httpBody)
        return (Data(), self.makeHTTPURLResponse(statusCode: 201))
      }

      let snakeCaseEncoder = JSONEncoder()
      snakeCaseEncoder.keyEncodingStrategy = .convertToSnakeCase

      try await sut.from("users")
        .insert(EncoderOverrideRow(userName: "abc"), encoder: snakeCaseEncoder)
        .execute()

      let body = try #require(capturedBody.value)
      let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
      #expect(json["user_name"] as? String == "abc")
      #expect(json["userName"] == nil)
    }

    @Test
    func updatePerCallEncoderOverridesClientDefault() async throws {
      let capturedBody = LockIsolated<Data?>(nil)
      let sut = makeSUTWithCustomFetch { request in
        capturedBody.setValue(request.httpBody)
        return (Data(), self.makeHTTPURLResponse(statusCode: 200))
      }

      let snakeCaseEncoder = JSONEncoder()
      snakeCaseEncoder.keyEncodingStrategy = .convertToSnakeCase

      try await sut.from("users")
        .update(EncoderOverrideRow(userName: "abc"), encoder: snakeCaseEncoder)
        .eq("id", value: 1)
        .execute()

      let body = try #require(capturedBody.value)
      let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
      #expect(json["user_name"] as? String == "abc")
      #expect(json["userName"] == nil)
    }

    @Test
    func upsertPerCallEncoderOverridesClientDefault() async throws {
      let capturedBody = LockIsolated<Data?>(nil)
      let sut = makeSUTWithCustomFetch { request in
        capturedBody.setValue(request.httpBody)
        return (Data(), self.makeHTTPURLResponse(statusCode: 201))
      }

      let snakeCaseEncoder = JSONEncoder()
      snakeCaseEncoder.keyEncodingStrategy = .convertToSnakeCase

      try await sut.from("users")
        .upsert(EncoderOverrideRow(userName: "abc"), encoder: snakeCaseEncoder)
        .execute()

      let body = try #require(capturedBody.value)
      let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
      #expect(json["user_name"] as? String == "abc")
      #expect(json["userName"] == nil)
    }

    @Test
    func executePerCallDecoderOverridesClientDefault() async throws {
      struct SnakeCasePayload: Decodable, Sendable {
        let userId: Int
      }

      let sut = makeSUTWithCustomFetch { _ in
        (Data(#"{"user_id": 1}"#.utf8), self.makeHTTPURLResponse(statusCode: 200))
      }

      // The client's default decoder has no key conversion, so it can't match `user_id` to `userId`.
      do {
        let _: SnakeCasePayload = try await sut.from("users").select().execute().value
        Issue.record("Expected a decoding error without a matching key strategy")
      } catch is DecodingError {}

      let snakeCaseDecoder = JSONDecoder()
      snakeCaseDecoder.keyDecodingStrategy = .convertFromSnakeCase

      let result: SnakeCasePayload =
        try await sut.from("users").select().execute(decoder: snakeCaseDecoder).value
      #expect(result.userId == 1)
    }

    @Test
    func errorDecodingIsUnaffectedByClientDecoderCustomization() async throws {
      // A decoder aggressive enough to remap every key would prevent `PostgrestError` from ever
      // finding its required `message` field, if it were used to decode the error response.
      // Error decoding must use a fixed internal decoder instead, decoupled from this setting.
      let poisonedDecoder = JSONDecoder()
      poisonedDecoder.keyDecodingStrategy = .custom { _ in TestCodingKey(stringValue: "unmatched") }

      let sut = makeSUTWithCustomFetch(decoder: poisonedDecoder) { _ in
        (
          Data(#"{"code":"PGRST000","message":"Bad Request"}"#.utf8),
          self.makeHTTPURLResponse(statusCode: 400)
        )
      }

      do {
        try await sut.from("users").select().execute()
        Issue.record("Expected PostgrestError to be thrown")
      } catch let error as PostgrestError {
        #expect(error.message == "Bad Request")
        #expect(error.code == "PGRST000")
      }
    }

    @Test
    func errorDecodingIsUnaffectedByPerCallDecoderOverride() async throws {
      let poisonedDecoder = JSONDecoder()
      poisonedDecoder.keyDecodingStrategy = .custom { _ in TestCodingKey(stringValue: "unmatched") }

      let sut = makeSUTWithCustomFetch { _ in
        (
          Data(#"{"code":"PGRST000","message":"Bad Request"}"#.utf8),
          self.makeHTTPURLResponse(statusCode: 400)
        )
      }

      do {
        let _: [User] = try await sut.from("users").select().execute(decoder: poisonedDecoder).value
        Issue.record("Expected PostgrestError to be thrown")
      } catch let error as PostgrestError {
        #expect(error.message == "Bad Request")
        #expect(error.code == "PGRST000")
      }
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
      decoder: JSONDecoder = PostgrestClient.Configuration.jsonDecoder,
      fetch: @escaping PostgrestClient.FetchHandler
    ) -> PostgrestClient {
      PostgrestClient(
        configuration: .init(url: url, fetch: fetch, decoder: decoder, retryEnabled: retryEnabled),
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

/// A row with a camelCase property, used to prove a custom `keyEncodingStrategy` was applied.
/// `keyEncodingStrategy` only affects keys derived from a type's synthesized `CodingKeys`, not
/// raw `Dictionary` keys, so this can't be a `[String: String]` literal.
private struct EncoderOverrideRow: Encodable, Sendable {
  let userName: String
}

/// A `CodingKey` that remaps to a fixed, unmatched key — used to simulate a decoder whose key
/// strategy is aggressive enough to break decoding of any fixed-shape response.
private struct TestCodingKey: CodingKey {
  var stringValue: String
  var intValue: Int? { nil }

  init(stringValue: String) {
    self.stringValue = stringValue
  }

  init?(intValue: Int) {
    nil
  }
}
