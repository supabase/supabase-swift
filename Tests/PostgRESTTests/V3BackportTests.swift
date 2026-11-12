import ConcurrencyExtras
import Foundation
import HTTPTypes
import Helpers
import Testing

@testable import PostgREST

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite
struct V3BackportTests {
  let client = PostgrestClient(
    configuration: PostgrestClient.Configuration(
      url: URL(string: "http://localhost:54321/rest/v1")!
    )
  )

  private func query(_ builder: PostgrestBuilder) -> [URLQueryItem] {
    builder.mutableState.request.query
  }

  // MARK: - Filter aliases

  @Test
  @available(*, deprecated, message: "Exercises the deprecated filter aliases.")
  func deprecatedFilterAliasesBuildTheSameQueryAsTheirReplacements() {
    func select() -> PostgrestFilterBuilder { client.from("t").select() }

    #expect(query(select().equals("c", value: "v")) == query(select().eq("c", value: "v")))
    #expect(query(select().notEquals("c", value: "v")) == query(select().neq("c", value: "v")))
    #expect(query(select().greaterThan("c", value: "v")) == query(select().gt("c", value: "v")))
    #expect(
      query(select().greaterThanOrEquals("c", value: "v")) == query(select().gte("c", value: "v")))
    #expect(query(select().lowerThan("c", value: "v")) == query(select().lt("c", value: "v")))
    #expect(
      query(select().lowerThanOrEquals("c", value: "v")) == query(select().lte("c", value: "v")))
    #expect(
      query(select().rangeLowerThan("c", range: "[1,2]"))
        == query(select().rangeLt("c", range: "[1,2]")))
    #expect(
      query(select().rangeGreaterThan("c", value: "[1,2]"))
        == query(select().rangeGt("c", range: "[1,2]")))
    #expect(
      query(select().rangeGreaterThanOrEquals("c", value: "[1,2]"))
        == query(select().rangeGte("c", range: "[1,2]")))
    #expect(
      query(select().rangeLowerThanOrEquals("c", value: "[1,2]"))
        == query(select().rangeLte("c", range: "[1,2]")))
    #expect(
      query(select().fts("c", query: "q", config: "english"))
        == query(select().textSearch("c", query: "q", config: "english")))
    #expect(
      query(select().fullTextSearch("c", query: "q", config: "english"))
        == query(select().textSearch("c", query: "q", config: "english")))
    #expect(
      query(select().plainToFullTextSearch("c", query: "q"))
        == query(select().textSearch("c", query: "q", type: .plain)))
    #expect(
      query(select().phraseToFullTextSearch("c", query: "q"))
        == query(select().textSearch("c", query: "q", type: .phrase)))
    #expect(
      query(select().webFullTextSearch("c", query: "q"))
        == query(select().textSearch("c", query: "q", type: .websearch)))
  }
}

// MARK: - v3 type names

extension V3BackportTests {
  @Test
  func postgrestReturningIsTheNameOfTheReturningOptions() throws {
    let returning: PostgrestReturning = .minimal
    let builder = try client.from("t").insert(["a": 1], returning: returning)

    #expect(builder.mutableState.request.headers[.prefer] == "return=minimal")
    #expect(PostgrestReturning.representation.rawValue == "representation")
    #expect(PostgrestReturning(rawValue: "minimal") == .minimal)
  }

  @Test
  func postgrestReturningOptionsStillNamesTheSameType() {
    let old: PostgrestReturningOptions = .representation
    let new: PostgrestReturning = old

    switch new {
    case .minimal: Issue.record("Expected representation.")
    case .representation: break
    }
  }

  @Test
  func postgrestOperatorIsTheTopLevelNameOfTheFilterOperator() {
    let nested: PostgrestFilterBuilder.Operator = .eq
    let topLevel: PostgrestOperator = nested

    #expect(topLevel == .eq)
    #expect(PostgrestOperator.allCases.count == PostgrestFilterBuilder.Operator.allCases.count)
    #expect(
      query(client.from("t").select().not("c", operator: PostgrestOperator.is, value: "null"))
        == [
          URLQueryItem(name: "select", value: "*"), URLQueryItem(name: "c", value: "not.is.null"),
        ]
    )
  }
}

// MARK: - Per-call coders and insert options

extension V3BackportTests {
  private struct Row: Codable, Equatable {
    var createdAt: Date
  }

  private static var secondsEncoder: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .secondsSince1970
    return encoder
  }

  private func body(_ builder: PostgrestBuilder) -> String? {
    builder.mutableState.request.body.map { String(decoding: $0, as: UTF8.self) }
  }

  private func prefer(_ builder: PostgrestBuilder) -> String? {
    builder.mutableState.request.headers[.prefer]
  }

  private func respondingClient(with json: String) -> PostgrestClient {
    PostgrestClient(
      configuration: PostgrestClient.Configuration(
        url: URL(string: "http://localhost:54321/rest/v1")!,
        fetch: { request in
          (
            Data(json.utf8),
            HTTPURLResponse(
              url: request.url!, statusCode: 200, httpVersion: nil,
              headerFields: ["sb-request-id": "req-1", "Content-Range": "0-0/1"])!
          )
        }
      )
    )
  }

  @Test
  func executeDecodesWithThePerCallDecoder() async throws {
    let client = respondingClient(with: #"{"createdAt":10}"#)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970

    let response: PostgrestResponse<Row> = try await client.from("t").select()
      .execute(options: FetchOptions(), decoder: decoder)
    let value: Row = try await client.from("t").select().execute(decoder: decoder).value

    #expect(response.value == Row(createdAt: Date(timeIntervalSince1970: 10)))
    #expect(value == response.value)
  }

  @Test
  func executeWithNilDecoderUsesTheClientDecoder() async throws {
    let client = respondingClient(with: #"{"id":1,"username":"a"}"#)

    let user: User = try await client.from("t").select().execute(decoder: nil).value

    #expect(user.id == 1)
  }

  @Test
  func v2ExecuteCallSitesKeepTheirMeaning() async throws {
    let client = respondingClient(with: #"{"id":1,"username":"a"}"#)

    let void = try await client.from("t").select().execute()
    let _: Void = void.value
    let withOptions = try await client.from("t").select().execute(options: FetchOptions())
    let _: Void = withOptions.value
    let user: User = try await client.from("t").select().execute().value
    let typed = try await client.from("t").select().execute() as PostgrestResponse<User>

    #expect(user.id == typed.value.id)
  }

  @Test
  func insertEncodesWithThePerCallEncoder() throws {
    let row = Row(createdAt: Date(timeIntervalSince1970: 10))

    let builder = try client.from("t").insert(row, encoder: Self.secondsEncoder)

    #expect(body(builder) == #"{"createdAt":10}"#)
    #expect(prefer(builder) == nil)
  }

  @Test
  func insertWithDefaultToNullFalseSendsMissingDefault() throws {
    let builder = try client.from("t")
      .insert(
        [["a": 1]], returning: PostgrestReturning.minimal, count: .exact, defaultToNull: false)

    #expect(prefer(builder) == "return=minimal,count=exact,missing=default")
    #expect(query(builder) == [URLQueryItem(name: "columns", value: #""a""#)])
  }

  @Test
  func insertWithDefaultToNullTrueSendsTheV2Request() throws {
    let old = try client.from("t").insert([["a": 1]], returning: .minimal, count: .exact)
    let new = try client.from("t")
      .insert([["a": 1]], returning: .minimal, count: .exact, defaultToNull: true, encoder: nil)

    #expect(prefer(new) == prefer(old))
    #expect(body(new) == body(old))
    #expect(query(new) == query(old))
  }

  @Test
  func upsertEncodesWithThePerCallEncoderAndKeepsTheV2Defaults() throws {
    let row = Row(createdAt: Date(timeIntervalSince1970: 10))

    let builder = try client.from("t").upsert(row, encoder: Self.secondsEncoder)

    #expect(body(builder) == #"{"createdAt":10}"#)
    #expect(prefer(builder) == "resolution=merge-duplicates,return=representation")
  }

  @Test
  func upsertWithDefaultToNullFalseSendsMissingDefault() throws {
    let builder = try client.from("t")
      .upsert([["a": 1]], onConflict: "a", ignoreDuplicates: true, defaultToNull: false)

    #expect(
      prefer(builder) == "resolution=ignore-duplicates,return=representation,missing=default")
    #expect(
      query(builder) == [
        URLQueryItem(name: "on_conflict", value: "a"),
        URLQueryItem(name: "columns", value: #""a""#),
      ])
  }

  @Test
  func updateEncodesWithThePerCallEncoderAndKeepsTheV2Defaults() throws {
    let row = Row(createdAt: Date(timeIntervalSince1970: 10))

    let builder = try client.from("t").update(row, count: .exact, encoder: Self.secondsEncoder)

    #expect(body(builder) == #"{"createdAt":10}"#)
    #expect(prefer(builder) == "return=representation,count=exact")
  }

  @Test
  func v2MutationCallSitesKeepTheirMeaning() throws {
    let inserted = try client.from("t").insert(["a": 1]).eq("a", value: 1)
    let upserted = try client.from("t").upsert(["a": 1], onConflict: "a").eq("a", value: 1)
    let updated = try client.from("t").update(["a": 1], returning: .minimal).eq("a", value: 1)

    #expect(prefer(inserted) == nil)
    #expect(prefer(upserted) == "resolution=merge-duplicates,return=representation")
    #expect(prefer(updated) == "return=minimal")
  }
}

// MARK: - Per-request modifiers

extension V3BackportTests {
  @Test
  func timeoutSetsTheRequestTimeout() {
    let builder = client.from("t").select().timeout(.milliseconds(2500))

    #expect(builder.mutableState.request.timeoutInterval == 2.5)
    #expect(builder.mutableState.request.urlRequest.timeoutInterval == 2.5)
  }

  @Test
  func timeoutKeepsTheBuilderTypeForChaining() {
    let builder: PostgrestFilterBuilder = client.from("t").select().timeout(.seconds(5))
      .eq("a", value: 1)

    #expect(builder.mutableState.request.timeoutInterval == 5)
  }

  @Test
  func requestTimeoutDefaultsToSixtySeconds() {
    #expect(client.from("t").select().mutableState.request.timeoutInterval == 60)
  }

  @Test
  func timeoutReachesTheFetchHandler() async throws {
    let seen = LockIsolated<TimeInterval?>(nil)
    let client = PostgrestClient(
      configuration: PostgrestClient.Configuration(
        url: URL(string: "http://localhost:54321/rest/v1")!,
        fetch: { request in
          seen.setValue(request.timeoutInterval)
          return (
            Data(),
            HTTPURLResponse(
              url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
          )
        }
      )
    )

    try await client.from("t").select().timeout(.seconds(7)).execute()

    #expect(seen.value == 7)
  }

  @Test
  func settingHeaderAddsOrReplacesTheHeader() {
    let name = HTTPField.Name("X-Custom")!
    let builder = client.from("t").select()
      .settingHeader(name: name, value: "a")
      .settingHeader(name: HTTPField.Name("x-custom")!, value: "b")

    #expect(builder.mutableState.request.headers[name] == "b")
  }

  @Test
  func settingHeaderMutatesTheReceiverAsTheV2BuildersDo() {
    let builder = client.from("t").select()

    builder.settingHeader(name: .prefer, value: "tx=rollback")

    #expect(builder.mutableState.request.headers[.prefer] == "tx=rollback")
  }

  @Test
  @available(*, deprecated, message: "Exercises the deprecated setHeader(name:value:).")
  func setHeaderStillSetsTheHeader() {
    let builder = client.from("t").select().setHeader(name: "X-Custom", value: "a")

    #expect(builder.mutableState.request.headers[HTTPField.Name("X-Custom")!] == "a")
  }
}
