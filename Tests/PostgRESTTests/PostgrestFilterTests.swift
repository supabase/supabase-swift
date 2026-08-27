//
//  PostgrestFilterTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 26/08/26.
//

import Foundation
import Testing

@testable import PostgREST

@Suite
struct PostgrestFilterTests {
  struct Todo: PostgrestRelation {
    static let relationName = "todos"
    static let schema = "public"
    static let selectString = "*"

    var id: Int

    struct Columns: Sendable {
      let id = PostgrestColumn<Todo, Int>("id")
    }

    static let columns = Columns()
  }

  private func rendered(_ filter: PostgrestFilter<Todo>) -> [String] {
    filter.queryItems().map { "\($0.name)=\($0.value ?? "")" }
  }

  private func c(_ column: String, _ op: String, _ value: String) -> PostgrestFilter<Todo> {
    PostgrestFilter<Todo>(column: column, operator: op, value: value)
  }

  /// PostgREST ANDs separate query parameters implicitly, so a top-level AND flattens.
  @Test
  func topLevelAndFlattensToSeparateQueryItems() {
    #expect(rendered(c("a", "eq", "1") && c("b", "gt", "2")) == ["a=eq.1", "b=gt.2"])
  }

  @Test
  func orRendersAsASingleParenthesisedParameter() {
    #expect(rendered(c("a", "eq", "1") || c("b", "gt", "2")) == ["or=(a.eq.1,b.gt.2)"])
  }

  @Test
  func anAndNestedInsideAnOrRendersAsAGroup() {
    let filter = (c("a", "eq", "1") && c("b", "gt", "2")) || c("c", "eq", "3")
    #expect(rendered(filter) == ["or=(and(a.eq.1,b.gt.2),c.eq.3)"])
  }

  /// Without associative flattening this renders `or=(or(a,b),c)` — accepted by PostgREST, but
  /// not what was written.
  @Test
  func repeatedOrFlattens() {
    let filter = c("a", "eq", "1") || c("b", "eq", "2") || c("c", "eq", "3")
    #expect(rendered(filter) == ["or=(a.eq.1,b.eq.2,c.eq.3)"])
  }

  @Test
  func repeatedAndFlattens() {
    let filter = c("a", "eq", "1") && c("b", "eq", "2") && c("c", "eq", "3")
    #expect(rendered(filter) == ["a=eq.1", "b=eq.2", "c=eq.3"])
  }

  @Test
  func negationPrefixesTheGroupOperator() {
    #expect(rendered(!(c("a", "eq", "1") && c("b", "gt", "2"))) == ["not.and=(a.eq.1,b.gt.2)"])
    #expect(rendered(!(c("a", "eq", "1") || c("b", "gt", "2"))) == ["not.or=(a.eq.1,b.gt.2)"])
  }

  @Test
  func negatingASingleComparisonPrefixesTheOperator() {
    #expect(rendered(!c("a", "eq", "1")) == ["a=not.eq.1"])
  }

  @Test
  func filtersReduceIntoOneFlatGroup() {
    let ids = [1, 2, 3]
    let filter = ids.dropFirst().reduce(c("id", "eq", "1")) { $0 || c("id", "eq", "\($1)") }
    #expect(rendered(filter) == ["or=(id.eq.1,id.eq.2,id.eq.3)"])
  }

  @Test
  func rawPassesAnOperandThroughUntouched() {
    #expect(rendered(.raw("cost::text", "eq.10")) == ["cost::text=eq.10"])
    #expect(rendered(!PostgrestFilter<Todo>.raw("x", "eq.1")) == ["x=not.eq.1"])
    #expect(rendered(c("id", "eq", "1") || .raw("x", "eq.2")) == ["or=(id.eq.1,x.eq.2)"])
  }

  /// Unescaped, `or=(name.eq.p(q),id.eq.3)` answers 200 with zero rows. Top level must *not* be
  /// quoted — `name=eq.a,b` is already correct there.
  @Test
  func groupOperandsAreEscapedAndTopLevelOnesAreNot() {
    #expect(rendered(c("name", "eq", "a,b")) == ["name=eq.a,b"])
    #expect(
      rendered(c("name", "eq", "a,b") || c("id", "eq", "3"))
        == ["or=(name.eq.\"a,b\",id.eq.3)"])
    #expect(
      rendered(c("name", "eq", "p(q)") || c("id", "eq", "3"))
        == ["or=(name.eq.\"p(q)\",id.eq.3)"])
  }

  /// `group` must collapse too, or `!!a || b` renders `not.not.` and 400s.
  @Test
  func doubleNegationCollapsesInBothPositions() {
    #expect(rendered(!(!c("id", "eq", "2"))) == ["id=eq.2"])
    #expect(rendered(!(!c("id", "eq", "2")) || c("id", "eq", "3")) == ["or=(id.eq.2,id.eq.3)"])
  }

  /// `or=(not.id.eq.2,…)` is a `PGRST100`; `or=(id.not.eq.2,…)` is the accepted form.
  ///
  /// A negated leaf takes a different `group()` branch than a plain one, so the escaping is
  /// pinned here too rather than assumed from the plain case.
  @Test
  func negatedLeafInsideAGroupMovesNotNextToTheOperator() {
    #expect(rendered(!c("a", "eq", "1") || c("b", "eq", "2")) == ["or=(a.not.eq.1,b.eq.2)"])
    #expect(
      rendered(!c("name", "eq", "p(q)") || c("id", "eq", "3"))
        == ["or=(name.not.eq.\"p(q)\",id.eq.3)"])
    #expect(
      rendered(!c("name", "eq", "a,b") || c("id", "eq", "3"))
        == ["or=(name.not.eq.\"a,b\",id.eq.3)"])
  }

  /// The same rule one level deeper.
  @Test
  func negatedLeafInsideANestedAndRendersInPlace() {
    let filter = (c("a", "eq", "1") && !c("b", "eq", "2")) || c("c", "eq", "3")
    #expect(rendered(filter) == ["or=(and(a.eq.1,b.not.eq.2),c.eq.3)"])
  }

  /// The group grammar reaches a raw node by ancestry, not by its immediate combinator: an `&&`
  /// nested under `||` is still rendered by `group()`, so a `::` in the column reaches the
  /// stricter grammar and 400s. Pinned because the rule is easy to state as "combine with `&&`",
  /// which is not the test.
  @Test
  func aRawLeafUnderAndNestedInOrStillReachesTheGroupGrammar() {
    let filter = (c("id", "eq", "1") && .raw("cost::text", "eq.10")) || c("id", "eq", "3")
    #expect(rendered(filter) == ["or=(and(id.eq.1,cost::text.eq.10),id.eq.3)"])
  }

  /// The same by way of `not.and`, which also routes its children through `group()`.
  @Test
  func aRawLeafUnderAndNestedInNotStillReachesTheGroupGrammar() {
    let filter = !(c("id", "eq", "1") && PostgrestFilter<Todo>.raw("cost::text", "eq.10"))
    #expect(rendered(filter) == ["not.and=(id.eq.1,cost::text.eq.10)"])
  }

  /// A negated `raw` leaf follows the same in-group rule as a negated comparison.
  @Test
  func negatedRawLeafInsideAGroupMovesNotNextToTheOperand() {
    #expect(
      rendered(c("id", "eq", "1") || !PostgrestFilter<Todo>.raw("x", "eq.2"))
        == ["or=(id.eq.1,x.not.eq.2)"])
  }

  /// The leaf rule above does not affect a negated group: `not.` stays in front of `and(…)`.
  @Test
  func negatingANestedGroupStillPrefixesTheGroupOperator() {
    let filter = !(c("a", "eq", "1") && c("b", "eq", "2")) || c("c", "eq", "3")
    #expect(rendered(filter) == ["or=(not.and(a.eq.1,b.eq.2),c.eq.3)"])
  }

  @Test
  func groupEscapingAppliesTwoLevelsDeep() {
    let filter = (c("a", "eq", "1") && c("name", "eq", "p(q)")) || c("id", "eq", "3")
    #expect(rendered(filter) == ["or=(and(a.eq.1,name.eq.\"p(q)\"),id.eq.3)"])
  }

  /// The three global operators must not make ordinary Boolean logic ambiguous.
  @Test
  func ordinaryBooleanLogicStillWorks() {
    func check(_ a: Bool, _ b: Bool, _ d: Bool) -> Bool { (a && b) || (!d && a) || (b && !a) }
    #expect(check(true, true, false) == true)
    #expect(check(false, false, true) == false)
  }
}
