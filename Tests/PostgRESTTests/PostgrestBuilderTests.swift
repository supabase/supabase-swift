//
//  PostgrestBuilderTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 20/08/24.
//

import ConcurrencyExtras
import Foundation
import HTTPTypes
import HTTPTypesFoundation
import Helpers
import TestHelpers
import Testing

@testable import PostgREST

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite
struct PostgrestBuilderTests {
  let fixture = try! PostgrestQueryFixture()
  var transport: RecordingTransport { fixture.transport }
  var url: URL { fixture.url }
  var sut: PostgrestClient { fixture.sut }

  @Test
  func customHeaderOnAPerCallBasis() throws {
    let url = URL(string: "http://localhost:54321/rest/v1")!
    let postgrest1 = try PostgrestClient(
      configuration: .init(url: url, headers: [.apikey: "foo"]))
    let postgrest2 = try postgrest1.rpc("void_func").settingHeader(
      name: .apikey, value: "bar")

    #expect(
      postgrest1.from("users").select().request.headerFields[.apikey] == "foo")
    #expect(postgrest2.request.headerFields[.apikey] == "bar")
  }

  @Test
  func executeWithNonSuccessStatusCode() async throws {
    transport.stub(
      .get, url.appendingPathComponent("users"), status: 400,
      data: Data(
        """
        {
          "message": "Bad Request"
        }
        """.utf8
      ))

    do {
      try await sut
        .from("users")
        .select()
        .execute()
      Issue.record("Expected error to be thrown")
    } catch let error as PostgrestError {
      #expect(error.kind == .server)
      #expect(error.message == "Bad Request")
      #expect(error.serverError?.message == "Bad Request")
      #expect(error.response?.status == 400)
    }
  }

  @Test
  func executeWithNonJSONError() async throws {
    transport.stub(
      .get, url.appendingPathComponent("users"), status: 400, data: Data("Bad Request".utf8))

    do {
      try await sut
        .from("users")
        .select()
        .execute()
      Issue.record("Expected error to be thrown")
    } catch let error as PostgrestError {
      #expect(error.kind == .server)
      #expect(error.serverError == nil)
      #expect(error.response?.body == Data("Bad Request".utf8))
      #expect(error.response?.status == 400)
    }
  }

  @Test
  func maybeSingleReturnsNilOnZeroRows() async throws {
    transport.stub(
      .get, url.appendingPathComponent("users"), status: 406,
      data: Data(
        """
        {
          "code": "PGRST116",
          "details": "Results contain 0 rows, application/vnd.pgrst.object+json requires 1 row",
          "message": "JSON object requested, multiple (or no) rows returned"
        }
        """.utf8
      ))

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
    transport.stub(
      .get, url.appendingPathComponent("users"), status: 406,
      data: Data(
        """
        {
          "code": "PGRST116",
          "details": "The result contains 0 rows",
          "message": "Cannot coerce the result to a single JSON object"
        }
        """.utf8
      ))

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
    transport.stub(
      .get, url.appendingPathComponent("users"), status: 406,
      data: Data(
        """
        {
          "code": "PGRST116",
          "details": "Results contain 2 rows, application/vnd.pgrst.object+json requires 1 row",
          "message": "JSON object requested, multiple (or no) rows returned"
        }
        """.utf8
      ))

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
    transport.stub(
      .get, url.appendingPathComponent("users"),
      data: Data(
        """
        {
          "id": 1,
          "username": "admin"
        }
        """.utf8
      ))

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
    transport.stub(.head, url.appendingPathComponent("users")) {
      #"""
      curl \
      	--head \
      	--header "Accept: application/json" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/0.0.0; platform=macOS; platform-version=0.0.0; runtime=swift; runtime-version=0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/rest/v1/users?select=*"
      """#
    }

    try await sut.from("users")
      .select()
      .execute(options: FetchOptions(head: true))
  }

  @Test
  func executeWithCount() async throws {
    transport.stub(.get, url.appendingPathComponent("users"), data: Data("[]".utf8)) {
      #"""
      curl \
      	--header "Accept: application/json" \
      	--header "Content-Type: application/json" \
      	--header "Prefer: count=exact" \
      	--header "X-Client-Info: postgrest-swift/0.0.0; platform=macOS; platform-version=0.0.0; runtime=swift; runtime-version=0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/rest/v1/users?select=*"
      """#
    }

    try await sut.from("users")
      .select()
      .execute(options: FetchOptions(count: .exact))
  }

  @Test
  func executeWithCustomSchema() async throws {
    transport.stub(.get, url.appendingPathComponent("users"), data: Data("[]".utf8)) {
      #"""
      curl \
      	--header "Accept: application/json" \
      	--header "Accept-Profile: private" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/0.0.0; platform=macOS; platform-version=0.0.0; runtime=swift; runtime-version=0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/rest/v1/users?select=*"
      """#
    }

    try await sut
      .schema("private")
      .from("users")
      .select()
      .execute()
  }

  @Test
  func executeWithCustomSchemaAndHeadMethod() async throws {
    transport.stub(.head, url.appendingPathComponent("users")) {
      #"""
      curl \
      	--head \
      	--header "Accept: application/json" \
      	--header "Accept-Profile: private" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/0.0.0; platform=macOS; platform-version=0.0.0; runtime=swift; runtime-version=0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/rest/v1/users?select=*"
      """#
    }

    try await sut
      .schema("private")
      .from("users")
      .select()
      .execute(options: FetchOptions(head: true))
  }

  @Test
  func executeWithCustomSchemaAndPostMethod() async throws {
    transport.stub(.post, url.appendingPathComponent("users"), status: 201) {
      #"""
      curl \
      	--request POST \
      	--header "Accept: application/json" \
      	--header "Content-Length: 19" \
      	--header "Content-Profile: private" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/0.0.0; platform=macOS; platform-version=0.0.0; runtime=swift; runtime-version=0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"username\":\"test\"}" \
      	"http://localhost:54321/rest/v1/users"
      """#
    }

    try await sut
      .schema("private")
      .from("users")
      .insert(["username": "test"])
      .execute()
  }

  @Test
  func settingHeader() {
    let query = sut.from("users")
      .select()
      .settingHeader(name: .init("key")!, value: "value")

    #expect(query.request.headerFields[.init("key")!] == "value")
  }

  @Test
  func insertPerCallEncoderOverridesClientDefault() async throws {
    let capturedBody = LockIsolated<Data?>(nil)
    let sut = try makeSUTWithCustomFetch { request in
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
    let sut = try makeSUTWithCustomFetch { request in
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
    let sut = try makeSUTWithCustomFetch { request in
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

    let sut = try makeSUTWithCustomFetch { _ in
      (Data(#"{"user_id": 1}"#.utf8), self.makeHTTPURLResponse(statusCode: 200))
    }

    do {
      let _: SnakeCasePayload = try await sut.from("users").select().execute().value
      Issue.record("Expected a decoding error without a matching key strategy")
    } catch let error as PostgrestError {
      #expect(error.kind == .decoding)
      #expect(error.underlyingError is DecodingError)
    }

    let snakeCaseDecoder = JSONDecoder()
    snakeCaseDecoder.keyDecodingStrategy = .convertFromSnakeCase

    let result: SnakeCasePayload =
      try await sut.from("users").select().execute(decoder: snakeCaseDecoder).value
    #expect(result.userId == 1)
  }

  @Test
  func errorDecodingIsUnaffectedByClientDecoderCustomization() async throws {
    let poisonedDecoder = JSONDecoder()
    poisonedDecoder.keyDecodingStrategy = .custom { _ in TestCodingKey(stringValue: "unmatched") }

    let sut = try makeSUTWithCustomFetch(decoder: poisonedDecoder) { _ in
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

    let sut = try makeSUTWithCustomFetch { _ in
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

  @Test
  func retryOn520ForGETRequest() async throws {
    struct MutableState {
      var callCount = 0
      var capturedHeaders = [[String: String]]()
    }

    let state = LockIsolated(MutableState())

    let sut = try makeSUTWithCustomFetch { request in
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

    let sut = try makeSUTWithCustomFetch { _ in
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

    let sut = try makeSUTWithCustomFetch { _ in
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

    let sut = try makeSUTWithCustomFetch { _ in
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

    let sut = try makeSUTWithCustomFetch { _ in
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
  func noRetryOn500ForGET() async throws {
    let callCount = LockIsolated(0)

    let sut = try makeSUTWithCustomFetch { _ in
      callCount.withValue { $0 += 1 }
      return (Data(), self.makeHTTPURLResponse(statusCode: 500))
    }

    do {
      try await sut.from("users").select().execute()
      Issue.record("Expected error to be thrown")
    } catch {
      #expect(callCount.value == 1)
    }
  }

  @Test
  func retryOn503ForGETRequest() async throws {
    let callCount = LockIsolated(0)

    let sut = try makeSUTWithCustomFetch { _ in
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

    let sut = try makeSUTWithCustomFetch { _ in
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

    let sut = try makeSUTWithCustomFetch { _ in
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

    let sut = try makeSUTWithCustomFetch { _ in
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

    let sut = try makeSUTWithCustomFetch { _ in
      callCount.withValue { $0 += 1 }
      return (Data(), self.makeHTTPURLResponse(statusCode: 520))
    }

    do {
      try await sut.from("users").select().execute()
      Issue.record("Expected error to be thrown")
    } catch {
      #expect(callCount.value == 4)
    }
  }

  @Test
  func perRequestRetryDisabled() async throws {
    let callCount = LockIsolated(0)

    let sut = try makeSUTWithCustomFetch { _ in
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
  func perCallTimeoutOverridesTheConfiguredTimeout() async throws {
    let seen = LockIsolated<[Duration?]>([])
    let sut = try PostgrestClient(
      configuration: .init(
        url: url,
        http: .init(
          transport: ClosureTransport { _, _ in
            seen.withValue { $0.append(RequestTimeout.current) }
            return (HTTPTypes.HTTPResponse(status: .ok), HTTPBody(Data("[]".utf8)))
          },
          timeout: .seconds(7))
      )
    )

    try await sut.from("users").select().execute()
    try await sut.from("users").select().timeout(.seconds(3)).execute()
    try await sut.from("users").select().timeout(.seconds(3)).order("id").execute()

    #expect(seen.value == [.seconds(7), .seconds(3), .seconds(3)])
  }

  @Test
  func clientLevelRetryDisabled() async throws {
    let callCount = LockIsolated(0)

    let sut = try makeSUTWithCustomFetch(retryEnabled: false) { _ in
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

    let sut = try makeSUTWithCustomFetch(retryEnabled: false) { _ in
      callCount.withValue { $0 += 1 }
      if callCount.value < 2 {
        return (Data(), self.makeHTTPURLResponse(statusCode: 520))
      }
      return (Data("[]".utf8), self.makeHTTPURLResponse(statusCode: 200))
    }

    let result: PostgrestResponse<[User]> = try await sut.from("users").select()
      .retry(enabled: true)
      .execute()
    #expect(callCount.value == 2)
    #expect(result.value.isEmpty)
  }

  @Test
  func transportFailureIsWrapped() async throws {
    let sut = try makeSUTWithCustomFetch(retryEnabled: false) { _ in
      throw URLError(.notConnectedToInternet)
    }

    do {
      try await sut.from("users").select().execute()
      Issue.record("Expected error to be thrown")
    } catch let error as PostgrestError {
      #expect(error.kind == .transport)
      #expect((error.underlyingError as? URLError)?.code == .notConnectedToInternet)
    } catch {
      Issue.record("Unexpected error \(error)")
    }
  }

  @Test
  func cancellationIsNotWrapped() async throws {
    let sut = try makeSUTWithCustomFetch(retryEnabled: false) { _ in throw CancellationError() }

    await #expect(throws: CancellationError.self) {
      try await sut.from("users").select().execute()
    }
  }

  @Test
  func customFetchErrorIsNotWrapped() async throws {
    struct FetchError: Error {}
    let sut = try makeSUTWithCustomFetch(retryEnabled: false) { _ in throw FetchError() }

    await #expect(throws: FetchError.self) {
      try await sut.from("users").select().execute()
    }
  }

  @Test
  func undecodableSuccessBodyIsWrapped() async throws {
    let sut = try makeSUTWithCustomFetch { _ in
      (Data("not json".utf8), self.makeHTTPURLResponse(statusCode: 200))
    }

    do {
      let _: [User] = try await sut.from("users").select().execute().value
      Issue.record("Expected error to be thrown")
    } catch let error as PostgrestError {
      #expect(error.kind == .decoding)
      #expect(error.underlyingError is DecodingError)
    } catch {
      Issue.record("Unexpected error \(error)")
    }
  }

  private func makeSUTWithCustomFetch(
    retryEnabled: Bool = true,
    decoder: JSONDecoder = PostgrestClient.Configuration.jsonDecoder,
    fetch: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)
  ) throws -> PostgrestClient {
    let transport = ClosureTransport { request, body in
      guard var urlRequest = URLRequest(httpRequest: request) else {
        throw URLError(.badURL)
      }
      if let body { urlRequest.httpBody = try await Data(collecting: body, upTo: .max) }
      let (data, response) = try await fetch(urlRequest)
      guard let head = (response as? HTTPURLResponse)?.httpResponse else {
        throw URLError(.badServerResponse)
      }
      return (head, data.isEmpty ? nil : HTTPBody(data))
    }
    return try PostgrestClient(
      configuration: .init(
        url: url, http: .init(transport: transport), decoder: decoder, retryEnabled: retryEnabled,
        clock: ImmediateRetryTestClock())
    )
  }

  private func makeHTTPURLResponse(statusCode: Int) -> HTTPURLResponse {
    HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
  }
}

struct ImmediateRetryTestClock: Clock {
  var now: ContinuousClock.Instant { ContinuousClock().now }
  var minimumResolution: ContinuousClock.Instant.Duration { ContinuousClock().minimumResolution }

  func sleep(until deadline: ContinuousClock.Instant, tolerance: Duration?) async throws {}
}

private struct EncoderOverrideRow: Encodable, Sendable {
  let userName: String
}

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
