//
//  PostgrestFilterCollectionTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 26/08/26.
//

import Foundation
import Testing

@testable import PostgREST

@Suite
struct PostgrestFilterCollectionTests {
  struct Post: PostgrestRelation {
    static let relationName = "posts"
    static let schema = "public"
    static let selectString = "*"

    var tags: [String]
    var scheduled: String
    var content: String

    struct Columns: Sendable {
      let tags = PostgrestColumn<Post, [String]>("tags")
      let scheduled = PostgrestColumn<Post, String>("scheduled")
      let content = PostgrestColumn<Post, String>("content")
    }

    static let columns = Columns()

    static func columnName(for keyPath: PartialKeyPath<Self>) -> String {
      switch keyPath {
      case \Self.tags: "tags"
      case \Self.scheduled: "scheduled"
      case \Self.content: "content"
      default: fatalError("unmapped key path")
      }
    }
  }

  private func rendered(_ filter: PostgrestFilter<Post>) -> String {
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

  /// The third operand shape `cs`/`cd` take: a JSON object literal, on a `jsonb` column.
  @Test
  func containmentOperatorsTakeJSONLiteral() {
    let content = Post.columns.content
    #expect(rendered(content.containsJSON(#"{"a":1}"#)) == #"content=cs.{"a":1}"#)
    #expect(rendered(content.containedByJSON(#"{"a":1}"#)) == #"content=cd.{"a":1}"#)
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
