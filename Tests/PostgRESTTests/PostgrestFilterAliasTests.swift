//
//  PostgrestFilterAliasTests.swift
//  PostgREST
//
//  Created by Guilherme Souza on 07/10/26.
//

import Foundation
import Testing

@testable import PostgREST

/// The deprecated aliases on the untyped builder still forward to their replacement, so a caller
/// who has not migrated yet gets the same request.
///
/// Each call below emits a deprecation warning on purpose. Swift Testing rejects
/// `@available(*, deprecated)` on a `@Suite` or `@Test`, directly or through an extension, so
/// there is no deprecated context to put the calls in; the warnings are the price of keeping the
/// coverage until the aliases go in v4 (SDK-2183), when this file goes with them.
@Suite
struct PostgrestFilterAliasTests {
  private func query(
    _ build: (PostgrestFilterBuilder) -> PostgrestFilterBuilder
  ) async throws -> String? {
    let capture = QueryCapture()
    _ = try await build(capture.client.from("users").select()).execute()
    return capture.query
  }

  private func expectSameQuery(
    _ alias: (PostgrestFilterBuilder) -> PostgrestFilterBuilder,
    as replacement: (PostgrestFilterBuilder) -> PostgrestFilterBuilder,
    sourceLocation: SourceLocation = #_sourceLocation
  ) async throws {
    let aliased = try await query(alias)
    let replaced = try await query(replacement)
    #expect(aliased == replaced, sourceLocation: sourceLocation)
    #expect(
      aliased != "select=*", "the filter has to reach the query", sourceLocation: sourceLocation)
  }

  @Test
  func comparisonAliasesForwardToTheirOperators() async throws {
    try await expectSameQuery({ $0.equals("a", value: "1") }, as: { $0.eq("a", value: "1") })
    try await expectSameQuery({ $0.notEquals("a", value: "1") }, as: { $0.neq("a", value: "1") })
    try await expectSameQuery({ $0.greaterThan("a", value: "1") }, as: { $0.gt("a", value: "1") })
    try await expectSameQuery(
      { $0.greaterThanOrEquals("a", value: "1") }, as: { $0.gte("a", value: "1") })
    try await expectSameQuery({ $0.lowerThan("a", value: "1") }, as: { $0.lt("a", value: "1") })
    try await expectSameQuery(
      { $0.lowerThanOrEquals("a", value: "1") }, as: { $0.lte("a", value: "1") })
  }

  @Test
  func rangeAliasesForwardToTheirOperators() async throws {
    try await expectSameQuery(
      { $0.rangeLowerThan("a", range: "[1,2)") }, as: { $0.rangeLt("a", range: "[1,2)") })
    try await expectSameQuery(
      { $0.rangeGreaterThan("a", value: "[1,2)") }, as: { $0.rangeGt("a", range: "[1,2)") })
    try await expectSameQuery(
      { $0.rangeGreaterThanOrEquals("a", value: "[1,2)") },
      as: { $0.rangeGte("a", range: "[1,2)") })
    try await expectSameQuery(
      { $0.rangeLowerThanOrEquals("a", value: "[1,2)") },
      as: { $0.rangeLte("a", range: "[1,2)") })
  }

  @Test
  func textSearchAliasesForwardToTextSearch() async throws {
    try await expectSameQuery(
      { $0.fullTextSearch("a", query: "cat", config: "english") },
      as: { $0.textSearch("a", query: "cat", config: "english") })
    try await expectSameQuery(
      { $0.plainToFullTextSearch("a", query: "cat") },
      as: { $0.textSearch("a", query: "cat", type: .plain) })
    try await expectSameQuery(
      { $0.phraseToFullTextSearch("a", query: "cat") },
      as: { $0.textSearch("a", query: "cat", type: .phrase) })
    try await expectSameQuery(
      { $0.webFullTextSearch("a", query: "cat") },
      as: { $0.textSearch("a", query: "cat", type: .websearch) })
    try await expectSameQuery(
      { $0.fts("a", query: "cat", config: "english") },
      as: { $0.textSearch("a", query: "cat", config: "english") })
  }
}
