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
