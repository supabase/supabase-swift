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
    var scheduled: _PostgresRange<_TSTZRange>
    var content: String
    var metadata: JSONValue

    struct Columns: Sendable {
      let tags = _PostgrestColumn<Post, [String]>("tags")
      let scheduled = _PostgrestColumn<Post, _PostgresRange<_TSTZRange>>("scheduled")
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

  @Test
  func arrayOperatorMembersAreEscaped() {
    let tags = Post.columns.tags
    #expect(rendered(tags.contains(["a{b"])) == "tags=cs.{\"a{b\"}")
    #expect(rendered(tags.containedBy(["a,b"])) == "tags=cd.{\"a,b\"}")
  }

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

  @Test
  func containmentOperatorsTakeARangeLiteral() {
    let s = Post.columns.scheduled
    #expect(rendered(s.containsRange("[21,22)")) == "scheduled=cs.[21,22)")
    #expect(rendered(s.containedByRange("[21,22)")) == "scheduled=cd.[21,22)")
    #expect(rendered(s.overlapsRange("[25,35)")) == "scheduled=ov.[25,35)")
  }

  @Test
  func containmentOperatorsTakeJSON() {
    let metadata = Post.columns.metadata
    #expect(
      rendered(metadata.containsJSON(["b": ["c": 2], "a": 1]))
        == #"metadata=cs.{"a":1,"b":{"c":2}}"#)
    #expect(rendered(metadata.containedByJSON(["a": 1])) == #"metadata=cd.{"a":1}"#)
  }

  @Test
  func aJSONOperandIsEncodedAsJSON() {
    let metadata = Post.columns.metadata
    #expect(rendered(metadata.containsJSON([20])) == "metadata=cs.[20]")
    #expect(rendered(metadata.containsJSON("x")) == #"metadata=cs."x""#)
    #expect(rendered(metadata.containsJSON(["url": "a/b"])) == #"metadata=cs.{"url":"a/b"}"#)
  }

  @Test
  func aJSONOperandIsQuotedInsideAGroup() {
    let metadata = Post.columns.metadata
    let filter = metadata.containsJSON(["a": 1, "n": 10]) || metadata.containsJSON(["n": 3])
    #expect(
      rendered(filter) == #"or=(metadata.cs."{\"a\":1,\"n\":10}",metadata.cs."{\"n\":3}")"#)
  }

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

  @Test
  func rangeOperandIsEscapedInsideOr() {
    let s = Post.columns.scheduled
    let content = Post.columns.content
    #expect(
      rendered(s.overlapsRange("[25,35)") || content.eq("x"))
        == #"or=(scheduled.ov."[25,35)",content.eq.x)"#)
  }
}
