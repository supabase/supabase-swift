//
//  PostgrestFilterCollectionTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 26/08/26.
//

import Foundation
import Testing

@_spi(Experimental) @testable import PostgREST

@Suite
struct PostgrestFilterCollectionTests {
  struct Post: _PostgrestRelation {
    static let relationName = "posts"
    static let selectString = "*"

    var tags: [String]
    var scheduled: _PostgresRange<Date>
    var content: String
    var metadata: JSONValue

    struct Columns: Sendable {
      let tags = _PostgrestColumn<Post, [String]>("tags")
      let scheduled = _PostgrestColumn<Post, _PostgresRange<Date>>("scheduled")
      let content = _PostgrestColumn<Post, String>("content")
      let metadata = _PostgrestColumn<Post, JSONValue>("metadata")
    }

    static let columns = Columns()
  }

  private func rendered(_ filter: _PostgrestFilter<Post>) -> String {
    filter.queryItems().map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&")
  }

  @Test
  func arrayOperatorsRenderABracedArray() {
    let tags = Post.columns.tags
    #expect(rendered(tags.contains(["swift"])) == "tags=cs.{swift}")
    #expect(rendered(tags.containedBy(["swift", "ios"])) == "tags=cd.{swift,ios}")
    #expect(rendered(tags.overlaps(["swift"])) == "tags=ov.{swift}")
  }

  /// A member containing a literal brace is what tells the two escapers apart: the array escaper
  /// quotes it, the filter escaper would let it through and corrupt the literal's delimiters.
  @Test
  func arrayOperatorMembersAreEscaped() {
    let tags = Post.columns.tags
    #expect(rendered(tags.contains(["a{b"])) == "tags=cs.{\"a{b\"}")
    #expect(rendered(tags.containedBy(["a,b"])) == "tags=cd.{\"a,b\"}")
  }

  /// `tags=cs.{}` matches every row whose column is non-null; a `NULL` column never matches.
  @Test
  func arrayOperatorsRenderAnEmptyArray() {
    let tags = Post.columns.tags
    #expect(rendered(tags.contains([])) == "tags=cs.{}")
  }

  @Test
  func rangeOperatorsRenderTheirAbbreviation() {
    let s = Post.columns.scheduled
    #expect(
      rendered(s.rangeLt("[2024-01-01,2024-02-01)")) == "scheduled=sl.[2024-01-01,2024-02-01)")
    #expect(rendered(s.rangeGt("[2024-01-01,)")) == "scheduled=sr.[2024-01-01,)")
    #expect(rendered(s.rangeGte("[2024-01-01,)")) == "scheduled=nxl.[2024-01-01,)")
    #expect(rendered(s.rangeLte("[2024-01-01,)")) == "scheduled=nxr.[2024-01-01,)")
    #expect(rendered(s.rangeAdjacent("[2024-01-01,)")) == "scheduled=adj.[2024-01-01,)")
  }

  /// Same wire operators as the array trio, but taking a range literal. Crossing the two shapes
  /// (`span=ov.{1,20}`) is a 400.
  @Test
  func containmentOperatorsTakeARangeLiteral() {
    let s = Post.columns.scheduled
    #expect(rendered(s.containsRange("[21,22)")) == "scheduled=cs.[21,22)")
    #expect(rendered(s.containedByRange("[21,22)")) == "scheduled=cd.[21,22)")
    #expect(rendered(s.overlapsRange("[25,35)")) == "scheduled=ov.[25,35)")
  }

  /// The third operand shape `cs`/`cd` take: a JSON value, on a `jsonb` column. Keys are sorted,
  /// which containment ignores.
  @Test
  func containmentOperatorsTakeJSON() {
    let metadata = Post.columns.metadata
    #expect(
      rendered(metadata.containsJSON(["b": ["c": 2], "a": 1]))
        == #"metadata=cs.{"a":1,"b":{"c":2}}"#)
    #expect(rendered(metadata.containedByJSON(["a": 1])) == #"metadata=cd.{"a":1}"#)
  }

  /// The operand is encoded as JSON, not as a filter value: `JSONValue`'s filter form renders
  /// `.array` as the Postgres literal `{20}` and `.string` bare, both a `22P02` against `jsonb`.
  @Test
  func aJSONOperandIsEncodedAsJSON() {
    let metadata = Post.columns.metadata
    #expect(rendered(metadata.containsJSON([20])) == "metadata=cs.[20]")
    #expect(rendered(metadata.containsJSON("x")) == #"metadata=cs."x""#)
    #expect(rendered(metadata.containsJSON(["url": "a/b"])) == #"metadata=cs.{"url":"a/b"}"#)
  }

  /// Inside a group the operand is quoted like any other value. PostgREST unquotes it before
  /// parsing the JSON.
  @Test
  func aJSONOperandIsQuotedInsideAGroup() {
    let metadata = Post.columns.metadata
    let filter = metadata.containsJSON(["a": 1, "n": 10]) || metadata.containsJSON(["n": 3])
    #expect(
      rendered(filter) == #"or=(metadata.cs."{\"a\":1,\"n\":10}",metadata.cs."{\"n\":3}")"#)
  }

  /// A non-finite `Double` has no JSON form. No stand-in operand is sent — `cs.null` matches
  /// JSON-null rows — so `execute()` throws before the request is built, alone or in a group.
  @Test(
    arguments: [
      { (c: Post.Columns) in c.metadata.containsJSON(["n": .double(.nan)]) },
      { (c: Post.Columns) in c.metadata.containedByJSON(.double(.infinity)) },
      { (c: Post.Columns) in c.content.eq("x") || !c.metadata.containsJSON([.double(.nan)]) },
    ] as [@Sendable (Post.Columns) -> _PostgrestFilter<Post>]
  )
  func aJSONOperandWithNoJSONFormFailsTheRequestBeforeItIsSent(
    filter: @Sendable (Post.Columns) -> _PostgrestFilter<Post>
  ) async throws {
    let capture = QueryCapture()
    do {
      _ = try await capture.client.from(Post.self).select().where(filter).execute()
      Issue.record("Expected an error")
    } catch let error as PostgrestError {
      #expect(error.kind == .invalidRequest)
    }
    #expect(capture.query == nil)
  }

  @Test
  func textSearchRendersConfigAndType() {
    let content = Post.columns.content
    #expect(rendered(content.textSearch("swift")) == "content=fts.swift")
    #expect(
      rendered(content.textSearch("swift", config: "english")) == "content=fts(english).swift")
    #expect(
      rendered(content.textSearch("swift", config: "english", type: .websearch))
        == "content=wfts(english).swift")
    #expect(rendered(content.textSearch("swift", type: .plain)) == "content=plfts.swift")
  }

  /// A range literal is the case that *needs* `group()`'s escaping: bare, the `)` in
  /// `or=(span.ov.[25,35),id.eq.3)` closes the logic group early and 400s. Routing these through
  /// `.raw` the way `in` does would produce exactly that.
  @Test
  func rangeOperandIsEscapedInsideOr() {
    let s = Post.columns.scheduled
    let content = Post.columns.content
    #expect(
      rendered(s.overlapsRange("[25,35)") || content.eq("x"))
        == #"or=(scheduled.ov."[25,35)",content.eq.x)"#)
  }
}
