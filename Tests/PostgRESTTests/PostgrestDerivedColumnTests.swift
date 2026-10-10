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

  /// A cast is select position only. Neither of these compiles, and both misbehave on the wire:
  ///
  ///     $0.cost.cast(to: .text).eq("10")    // 200, cast dropped, wrong rows
  ///     $0.cost.cast(to: .text).asc()       // 400 PGRST100
  @Test
  func aCastIsSelectableAndNothingElse() {
    let costText = Item.columns.cost.cast(to: .text)
    #expect((costText as Any) is any _PostgrestColumnExpression)
    #expect((costText as Any) is any _PostgrestFilterableExpression == false)
    #expect((costText as Any) is any _PostgrestOrderableExpression == false)
  }

  /// A JSON path on a cast to `.text` does not compile, since `String` is not a JSON column type.
  /// On a cast to a JSON type it compiles, but inherits the cast's select-only position.
  /// PostgREST rejects `cost::text->>k` in every position, so select-only is as tight as the
  /// type system can get here without forbidding the chain outright.
  @Test
  func castingThenJSONPathInheritsTheCastsSelectOnlyPosition() {
    let composed = Item.columns.cost.cast(to: _PostgrestCastTarget<JSONValue>("jsonb")).jsonText(
      "k")
    #expect(composed.postgrestExpression == #"cost::jsonb->>"k""#)
    #expect((composed as Any) is any _PostgrestFilterableExpression == false)
    #expect((composed as Any) is any _PostgrestOrderableExpression == false)
  }

  /// A Postgres type with no shipped target is still reachable, and still says what it produces.
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

  /// `->` produces `jsonb`, so a path is a `JSONValue` and chains on and filters by containment.
  @Test
  func jsonObjectReturnsJSONValue() {
    let meta: _PostgrestDerivedExpression<Item, JSONValue, _PostgrestEveryPosition> =
      Item.columns.data.jsonObject("meta")
    #expect(meta.jsonText("k").postgrestExpression == #"data->"meta"->>"k""#)
    #expect(rendered(meta.containsJSON(["c": 2])) == #"data->"meta"=cs.{"c":2}"#)
  }

  /// PostgREST reads a `jsonb` comparison's operand as JSON. In filter form `.string("1")` went out
  /// as `eq.1` and matched the number 1, and `.null` as `eq.NULL`, a `22P02`.
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

  /// List members and grouped operands are JSON first, then quoted like any other value.
  @Test
  func aJSONOperandIsQuotedInAListAndAGroup() {
    let a = Item.columns.data.jsonObject("a")
    #expect(rendered(a.in(["1", 2])) == #"data->"a"=in.("\"1\"",2)"#)
    #expect(
      rendered(a.eq("x,y") || Item.columns.cost.eq(2))
        == #"or=(data->"a".eq."\"x,y\"",cost.eq.2.0)"#)
  }

  /// A non-finite `Double` has no JSON form, so a comparison or `in` with it is never sent. No
  /// stand-in operand is: `eq.null` matches JSON-null rows.
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

  /// Bare, `->0` is an array index and `->a.b` is a `PGRST100`; quoted, both reach the key.
  @Test
  func aKeyIsAlwaysQuoted() {
    #expect(Item.columns.data.jsonText("0").postgrestExpression == #"data->>"0""#)
    #expect(Item.columns.data.jsonObject("a.b").postgrestExpression == #"data->"a.b""#)
    #expect(Item.columns.data.jsonText("p(q),r").postgrestExpression == #"data->>"p(q),r""#)
    #expect(Item.columns.data.jsonText("").postgrestExpression == #"data->>"""#)
  }

  /// Inside the quotes PostgREST reads a backslash as escaping the next character, so a stray
  /// `\` is dropped (`"b\s"` reads key `bs`) and an unescaped `"` ends the key early.
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

  /// Every operator applies to a JSON path, because it conforms to the filterable protocol.
  @Test
  func aJSONPathComposesWithEveryOperator() {
    let name = Item.columns.data.jsonText("name")
    #expect(rendered(name.eq("Ada")) == #"data->>"name"=eq.Ada"#)
    #expect(rendered(name.like("A%")) == #"data->>"name"=like.A%"#)
    #expect(rendered(name.in(["Ada", "Bob"])) == #"data->>"name"=in.(Ada,Bob)"#)
    #expect((name as Any) is any _PostgrestOrderableExpression)
  }

  /// A JSON extraction is null-testable whatever the column's own nullability: `data` is a
  /// `NOT NULL` column here, and `data->>name` is still `NULL` when the key is absent. Verified
  /// on PostgREST 16.1 — `data->>name=is.null` answers 200 with the rows whose extracted value
  /// is null.
  @Test
  func aJSONPathIsNullTestableOnANotNullColumn() {
    #expect(rendered(Item.columns.data.jsonText("name").isNull()) == #"data->>"name"=is.null"#)
    // No `isNotNull()` anywhere on the surface; `!` covers it.
    #expect(rendered(!Item.columns.data.jsonText("name").isNull()) == #"data->>"name"=not.is.null"#)
  }

  /// The operator is keyed on the filterable position, so a select-only derivation does not pick
  /// it up. Neither call must compile:
  ///
  ///     $0.cost.cast(to: .text).isNull()   // does not conform to _PostgrestNullableExpression
  ///     $0.cost.sum().isNull()             // same
  ///
  /// Nor does a `NOT NULL` stored column gain it — that guarantee is what put `isNull()` on a
  /// refinement rather than on the base protocol.
  @Test
  func onlyAFilterableDerivationIsNullTestable() {
    #expect((Item.columns.data.jsonText("name") as Any) is any _PostgrestNullableExpression)
    #expect((Item.columns.cost.cast(to: .text) as Any) is any _PostgrestNullableExpression == false)
    #expect((Item.columns.cost.sum() as Any) is any _PostgrestNullableExpression == false)
    #expect((Item.columns.cost as Any) is any _PostgrestNullableExpression == false)
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
        == [#"or=(data->>"name".eq.Ada,cost.eq.2.0)"#])
  }

  /// A JSON path orders like any other orderable expression.
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
