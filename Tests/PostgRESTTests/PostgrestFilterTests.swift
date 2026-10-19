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
  struct Todo: _PostgrestRelation {
    static let relationName = "todos"
    static let selectString = "*"

    var id: Int

    struct Columns: Sendable {
      let id = _PostgrestColumn<Todo, Int>("id")
    }

    static let columns = Columns()
  }

  private func rendered(_ filter: _PostgrestFilter<Todo>) -> [String] {
    filter.queryItems().map { "\($0.name)=\($0.value ?? "")" }
  }

  private func c(
    _ column: String, _ op: _PostgrestFilterOperator, _ value: String
  ) -> _PostgrestFilter<Todo> {
    _PostgrestFilter<Todo>(column: column, operator: op, value: value)
  }

  @Test
  func topLevelAndFlattensToSeparateQueryItems() {
    #expect(rendered(c("a", .eq, "1") && c("b", .gt, "2")) == ["a=eq.1", "b=gt.2"])
  }

  @Test
  func orRendersAsASingleParenthesisedParameter() {
    #expect(rendered(c("a", .eq, "1") || c("b", .gt, "2")) == ["or=(a.eq.1,b.gt.2)"])
  }

  @Test
  func anAndNestedInsideAnOrRendersAsAGroup() {
    let filter = (c("a", .eq, "1") && c("b", .gt, "2")) || c("c", .eq, "3")
    #expect(rendered(filter) == ["or=(and(a.eq.1,b.gt.2),c.eq.3)"])
  }

  @Test
  func repeatedOrFlattens() {
    let filter = c("a", .eq, "1") || c("b", .eq, "2") || c("c", .eq, "3")
    #expect(rendered(filter) == ["or=(a.eq.1,b.eq.2,c.eq.3)"])
  }

  @Test
  func repeatedAndFlattens() {
    let filter = c("a", .eq, "1") && c("b", .eq, "2") && c("c", .eq, "3")
    #expect(rendered(filter) == ["a=eq.1", "b=eq.2", "c=eq.3"])
  }

  @Test
  func negationPrefixesTheGroupOperator() {
    #expect(rendered(!(c("a", .eq, "1") && c("b", .gt, "2"))) == ["not.and=(a.eq.1,b.gt.2)"])
    #expect(rendered(!(c("a", .eq, "1") || c("b", .gt, "2"))) == ["not.or=(a.eq.1,b.gt.2)"])
  }

  @Test
  func negatingASingleComparisonPrefixesTheOperator() {
    #expect(rendered(!c("a", .eq, "1")) == ["a=not.eq.1"])
  }

  @Test
  func filtersReduceIntoOneFlatGroup() {
    let ids = [1, 2, 3]
    let filter = ids.dropFirst().reduce(c("id", .eq, "1")) { $0 || c("id", .eq, "\($1)") }
    #expect(rendered(filter) == ["or=(id.eq.1,id.eq.2,id.eq.3)"])
  }

  @Test
  func rawPassesAnOperandThroughUntouched() {
    #expect(rendered(.raw("cost::text", "eq.10")) == ["cost::text=eq.10"])
    #expect(rendered(!_PostgrestFilter<Todo>.raw("x", "eq.1")) == ["x=not.eq.1"])
    #expect(rendered(c("id", .eq, "1") || .raw("x", "eq.2")) == ["or=(id.eq.1,x.eq.2)"])
  }

  @Test
  func groupOperandsAreEscapedAndTopLevelOnesAreNot() {
    #expect(rendered(c("name", .eq, "a,b")) == ["name=eq.a,b"])
    #expect(
      rendered(c("name", .eq, "a,b") || c("id", .eq, "3"))
        == ["or=(name.eq.\"a,b\",id.eq.3)"])
    #expect(
      rendered(c("name", .eq, "p(q)") || c("id", .eq, "3"))
        == ["or=(name.eq.\"p(q)\",id.eq.3)"])
  }

  @Test
  func doubleNegationCollapsesInBothPositions() {
    #expect(rendered(!(!c("id", .eq, "2"))) == ["id=eq.2"])
    #expect(rendered(!(!c("id", .eq, "2")) || c("id", .eq, "3")) == ["or=(id.eq.2,id.eq.3)"])
  }

  @Test
  func negatedLeafInsideAGroupMovesNotNextToTheOperator() {
    #expect(rendered(!c("a", .eq, "1") || c("b", .eq, "2")) == ["or=(a.not.eq.1,b.eq.2)"])
    #expect(
      rendered(!c("name", .eq, "p(q)") || c("id", .eq, "3"))
        == ["or=(name.not.eq.\"p(q)\",id.eq.3)"])
    #expect(
      rendered(!c("name", .eq, "a,b") || c("id", .eq, "3"))
        == ["or=(name.not.eq.\"a,b\",id.eq.3)"])
  }

  @Test
  func negatedLeafInsideANestedAndRendersInPlace() {
    let filter = (c("a", .eq, "1") && !c("b", .eq, "2")) || c("c", .eq, "3")
    #expect(rendered(filter) == ["or=(and(a.eq.1,b.not.eq.2),c.eq.3)"])
  }

  @Test
  func aRawLeafUnderAndNestedInOrStillReachesTheGroupGrammar() {
    let filter = (c("id", .eq, "1") && .raw("cost::text", "eq.10")) || c("id", .eq, "3")
    #expect(rendered(filter) == ["or=(and(id.eq.1,cost::text.eq.10),id.eq.3)"])
  }

  @Test
  func aRawLeafUnderAndNestedInNotStillReachesTheGroupGrammar() {
    let filter = !(c("id", .eq, "1") && _PostgrestFilter<Todo>.raw("cost::text", "eq.10"))
    #expect(rendered(filter) == ["not.and=(id.eq.1,cost::text.eq.10)"])
  }

  @Test
  func negatedRawLeafInsideAGroupMovesNotNextToTheOperand() {
    #expect(
      rendered(c("id", .eq, "1") || !_PostgrestFilter<Todo>.raw("x", "eq.2"))
        == ["or=(id.eq.1,x.not.eq.2)"])
  }

  @Test
  func negatingANestedGroupStillPrefixesTheGroupOperator() {
    let filter = !(c("a", .eq, "1") && c("b", .eq, "2")) || c("c", .eq, "3")
    #expect(rendered(filter) == ["or=(not.and(a.eq.1,b.eq.2),c.eq.3)"])
  }

  @Test
  func groupEscapingAppliesTwoLevelsDeep() {
    let filter = (c("a", .eq, "1") && c("name", .eq, "p(q)")) || c("id", .eq, "3")
    #expect(rendered(filter) == ["or=(and(a.eq.1,name.eq.\"p(q)\"),id.eq.3)"])
  }

  @Test
  func ordinaryBooleanLogicStillWorks() {
    func check(_ a: Bool, _ b: Bool, _ d: Bool) -> Bool { (a && b) || (!d && a) || (b && !a) }
    #expect(check(true, true, false) == true)
    #expect(check(false, false, true) == false)
  }
}
