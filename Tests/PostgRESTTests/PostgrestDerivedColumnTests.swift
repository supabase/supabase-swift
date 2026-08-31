//
//  PostgrestDerivedColumnTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 26/08/26.
//

import Foundation
import Testing

@testable import PostgREST

@Suite
struct PostgrestDerivedColumnTests {
  struct Item: PostgrestRelation {
    static let relationName = "items"
    static let schema = "public"
    static let selectString = "*"

    var cost: Double
    var data: String

    struct Columns: Sendable {
      let cost = PostgrestColumn<Item, Double>("cost")
      let data = PostgrestColumn<Item, String>("data")
    }

    static let columns = Columns()
  }

  private func rendered(_ filter: PostgrestFilter<Item>) -> String {
    filter.queryItems().map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&")
  }

  @Test
  func aCastRendersTheDoubleColonForm() {
    #expect(Item.columns.cost.cast(to: .text).postgrestExpression == "cost::text")
    #expect(Item.columns.cost.cast(to: .int).postgrestExpression == "cost::int")
  }

  /// A cast is select position only. Neither of these compiles, and both misbehave on the wire:
  ///
  ///     $0.cost.cast(to: .text).eq("10")    // 200, cast dropped, wrong rows
  ///     $0.cost.cast(to: .text).asc()       // 400 PGRST100
  @Test
  func aCastIsSelectableAndNothingElse() {
    let costText = Item.columns.cost.cast(to: .text)
    #expect((costText as Any) is any PostgrestColumnExpression)
    #expect((costText as Any) is any PostgrestFilterableExpression == false)
    #expect((costText as Any) is any PostgrestOrderableExpression == false)
  }

  /// A JSON path chained onto a cast **compiles**, since both are declared on the base protocol,
  /// but PostgREST rejects the result. The rendering pinned here is therefore not a form to send
  /// — it records the compiling-but-rejected shape so a change to the hierarchy surfaces here.
  @Test
  func castingThenJSONPathCompilesButPostgRESTRejectsIt() {
    let composed = Item.columns.cost.cast(to: .text).jsonText("k")
    #expect(composed.postgrestExpression == "cost::text->>k")
    #expect((composed as Any) is any PostgrestFilterableExpression)
  }

  /// A Postgres type with no shipped target is still reachable, and still says what it produces.
  @Test
  func aCustomTargetNamesItsOwnSwiftType() {
    let citext = PostgrestCastTarget<String>("citext")
    #expect(Item.columns.data.cast(to: citext).postgrestExpression == "data::citext")
  }

  @Test
  func jsonPathsRenderTheirArrows() {
    #expect(Item.columns.data.jsonText("name").postgrestExpression == "data->>name")
    #expect(Item.columns.data.jsonObject("meta").postgrestExpression == "data->meta")
  }

  /// Every operator applies to a JSON path, because it conforms to the filterable protocol.
  @Test
  func aJSONPathComposesWithEveryOperator() {
    let name = Item.columns.data.jsonText("name")
    #expect(rendered(name.eq("Ada")) == "data->>name=eq.Ada")
    #expect(rendered(name.like("A%")) == "data->>name=like.A%")
    #expect(rendered(name.in(["Ada", "Bob"])) == "data->>name=in.(Ada,Bob)")
    #expect((name as Any) is any PostgrestOrderableExpression)
  }

  /// A JSON path survives a logic tree, which a cast does not.
  ///
  /// `cost` is a `Double` column, so `.eq(2)` renders `cost.eq.2.0` — what the SDK actually
  /// sends, not `cost.eq.2`.
  @Test
  func aJSONPathWorksInsideAGroup() {
    let filter = Item.columns.data.jsonText("name").eq("Ada") || Item.columns.cost.eq(2)
    #expect(
      filter.queryItems().map { "\($0.name)=\($0.value ?? "")" }
        == ["or=(data->>name.eq.Ada,cost.eq.2.0)"])
  }

  /// A JSON path orders like any other orderable expression.
  @Test
  func orderAcceptsJSONPaths() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from(Item.self)
      .select()
      .order { $0.data.jsonText("name").asc() }
      .execute()
    #expect(capture.query?.contains("order=data->>name.asc") == true)
  }
}
