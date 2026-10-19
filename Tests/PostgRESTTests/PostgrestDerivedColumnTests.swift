//
//  PostgrestDerivedColumnTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 26/08/26.
//

import Foundation
import Testing

@_spi(Experimental) @testable import PostgREST

@Suite
struct PostgrestDerivedColumnTests {
  struct Item: _PostgrestRelation {
    static let relationName = "items"
    static let selectString = "*"

    var cost: Double
    var data: JSONValue

    struct Columns: Sendable {
      let cost = _PostgrestColumn<Item, Double>("cost")
      let data = _PostgrestColumn<Item, JSONValue>("data")
    }

    static let columns = Columns()
  }

  private func rendered(_ filter: _PostgrestFilter<Item>) -> String {
    filter.queryItems().map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&")
  }

  @Test
  func aCastRendersTheDoubleColonForm() {
    #expect(Item.columns.cost.cast(to: .text).postgrestExpression == "cost::text")
    #expect(Item.columns.cost.cast(to: .int).postgrestExpression == "cost::int")
  }

  @Test
  func aCastIsSelectableAndNothingElse() {
    let costText = Item.columns.cost.cast(to: .text)
    #expect((costText as Any) is any _PostgrestColumnExpression)
    #expect((costText as Any) is any _PostgrestFilterableExpression == false)
    #expect((costText as Any) is any _PostgrestOrderableExpression == false)
  }

  @Test
  func castingThenJSONPathInheritsTheCastsSelectOnlyPosition() {
    let composed = Item.columns.cost.cast(to: _PostgrestCastTarget<JSONValue>("jsonb")).jsonText(
      "k")
    #expect(composed.postgrestExpression == #"cost::jsonb->>"k""#)
    #expect((composed as Any) is any _PostgrestFilterableExpression == false)
    #expect((composed as Any) is any _PostgrestOrderableExpression == false)
  }

  @Test
  func aCustomTargetNamesItsOwnSwiftType() {
    let citext = _PostgrestCastTarget<String>("citext")
    #expect(Item.columns.data.cast(to: citext).postgrestExpression == "data::citext")
  }

  @Test
  func jsonPathsRenderTheirArrows() {
    #expect(Item.columns.data.jsonText("name").postgrestExpression == #"data->>"name""#)
    #expect(Item.columns.data.jsonObject("meta").postgrestExpression == #"data->"meta""#)
  }

  @Test
  func jsonObjectReturnsJSONValue() {
    let meta: _PostgrestDerivedExpression<Item, JSONValue, _PostgrestEveryPosition> =
      Item.columns.data.jsonObject("meta")
    #expect(meta.jsonText("k").postgrestExpression == #"data->"meta"->>"k""#)
    #expect(rendered(meta.containsJSON(["c": 2])) == #"data->"meta"=cs.{"c":2}"#)
  }

  @Test
  func aJSONComparisonEncodesItsOperandAsJSON() {
    let a = Item.columns.data.jsonObject("a")
    #expect(rendered(a.eq("1")) == #"data->"a"=eq."1""#)
    #expect(rendered(a.eq(1)) == #"data->"a"=eq.1"#)
    #expect(rendered(a.gt(2)) == #"data->"a"=gt.2"#)
    #expect(rendered(a.eq(.null)) == #"data->"a"=eq.null"#)
    #expect(rendered(a.eq(["c": 2])) == #"data->"a"=eq.{"c":2}"#)
    #expect(rendered(a.neq("1")) == #"data->"a"=neq."1""#)
    #expect(rendered(a.isDistinct("1")) == #"data->"a"=isdistinct."1""#)
    #expect(rendered(Item.columns.data.eq(["a": 1])) == #"data=eq.{"a":1}"#)
  }

  @Test
  func aJSONOperandIsQuotedInAListAndAGroup() {
    let a = Item.columns.data.jsonObject("a")
    #expect(rendered(a.in(["1", 2])) == #"data->"a"=in.("\"1\"",2)"#)
    #expect(
      rendered(a.eq("x,y") || Item.columns.cost.eq(2))
        == #"or=(data->"a".eq."\"x,y\"",cost.eq.2.0)"#)
  }

  @Test(
    arguments: [
      { (c: Item.Columns) in c.data.jsonObject("a").eq(.double(.nan)) },
      { (c: Item.Columns) in c.data.jsonObject("a").in([1, .double(.infinity)]) },
      { (c: Item.Columns) in c.cost.eq(2) || c.data.eq(["n": .double(.nan)]) },
    ] as [@Sendable (Item.Columns) -> _PostgrestFilter<Item>]
  )
  func aComparisonWithNoJSONFormFailsTheRequestBeforeItIsSent(
    filter: @Sendable (Item.Columns) -> _PostgrestFilter<Item>
  ) async throws {
    let capture = QueryCapture()
    do {
      _ = try await capture.client.from(Item.self).select().where(filter).execute()
      Issue.record("Expected an error")
    } catch let error as PostgrestError {
      #expect(error.kind == .invalidRequest)
    }
    #expect(capture.query == nil)
  }

  @Test
  func aKeyIsAlwaysQuoted() {
    #expect(Item.columns.data.jsonText("0").postgrestExpression == #"data->>"0""#)
    #expect(Item.columns.data.jsonObject("a.b").postgrestExpression == #"data->"a.b""#)
    #expect(Item.columns.data.jsonText("p(q),r").postgrestExpression == #"data->>"p(q),r""#)
    #expect(Item.columns.data.jsonText("").postgrestExpression == #"data->>"""#)
  }

  @Test
  func aKeyEscapesQuotesAndBackslashes() {
    #expect(Item.columns.data.jsonText(#"q"t"#).postgrestExpression == #"data->>"q\"t""#)
    #expect(Item.columns.data.jsonText(#"b\s"#).postgrestExpression == #"data->>"b\\s""#)
  }

  @Test
  func anIndexIsBare() {
    #expect(Item.columns.data.jsonObject(0).postgrestExpression == "data->0")
    #expect(Item.columns.data.jsonText(-1).postgrestExpression == "data->>-1")
    #expect(
      Item.columns.data.jsonObject("tags").jsonText(1).postgrestExpression
        == #"data->"tags"->>1"#)
  }

  @Test
  func aJSONPathComposesWithEveryOperator() {
    let name = Item.columns.data.jsonText("name")
    #expect(rendered(name.eq("Ada")) == #"data->>"name"=eq.Ada"#)
    #expect(rendered(name.like("A%")) == #"data->>"name"=like.A%"#)
    #expect(rendered(name.in(["Ada", "Bob"])) == #"data->>"name"=in.(Ada,Bob)"#)
    #expect((name as Any) is any _PostgrestOrderableExpression)
  }

  @Test
  func aJSONPathIsNullTestableOnANotNullColumn() {
    #expect(rendered(Item.columns.data.jsonText("name").isNull()) == #"data->>"name"=is.null"#)
    // No `isNotNull()` anywhere on the surface; `!` covers it.
    #expect(rendered(!Item.columns.data.jsonText("name").isNull()) == #"data->>"name"=not.is.null"#)
  }

  @Test
  func onlyAFilterableDerivationIsNullTestable() {
    #expect((Item.columns.data.jsonText("name") as Any) is any _PostgrestNullableExpression)
    #expect((Item.columns.cost.cast(to: .text) as Any) is any _PostgrestNullableExpression == false)
    #expect((Item.columns.cost.sum() as Any) is any _PostgrestNullableExpression == false)
    #expect((Item.columns.cost as Any) is any _PostgrestNullableExpression == false)
  }

  @Test
  func aJSONPathWorksInsideAGroup() {
    let filter = Item.columns.data.jsonText("name").eq("Ada") || Item.columns.cost.eq(2)
    #expect(
      filter.queryItems().map { "\($0.name)=\($0.value ?? "")" }
        == [#"or=(data->>"name".eq.Ada,cost.eq.2.0)"#])
  }

  @Test
  func orderAcceptsJSONPaths() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from(Item.self)
      .select()
      .order { $0.data.jsonText("name").asc() }
      .execute()
    #expect(capture.query?.contains(#"order=data->>"name".asc"#) == true)
  }
}
