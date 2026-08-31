//
//  PostgrestFilterComparisonTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 26/08/26.
//

import Foundation
import Testing

@testable import PostgREST

@Suite
struct PostgrestFilterComparisonTests {
  struct Todo: PostgrestRelation {
    static let relationName = "todos"
    static let schema = "public"
    static let selectString = "*"

    var id: Int
    var isDone: Bool
    var dueDate: Date?

    struct Columns: Sendable {
      let id = PostgrestColumn<Todo, Int>("id")
      let isDone = PostgrestColumn<Todo, Bool>("is_done")
      let dueDate = PostgrestNullableColumn<Todo, Date>("due_at")
    }

    static let columns = Columns()
  }

  private func rendered(_ filter: PostgrestFilter<Todo>) -> String {
    filter.queryItems().map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&")
  }

  @Test
  func everyComparisonRendersItsOperator() {
    let c = Todo.columns
    #expect(rendered(c.isDone.eq(false)) == "is_done=eq.false")
    #expect(rendered(c.isDone.neq(false)) == "is_done=neq.false")
    #expect(rendered(c.id.gt(3)) == "id=gt.3")
    #expect(rendered(c.id.gte(3)) == "id=gte.3")
    #expect(rendered(c.id.lt(3)) == "id=lt.3")
    #expect(rendered(c.id.lte(3)) == "id=lte.3")
    #expect(rendered(c.id.isDistinct(3)) == "id=isdistinct.3")
  }

  /// There is no `isNotNull()`; `!` covers it. `isNull()` does not compile on a `NOT NULL`
  /// column — `$0.isDone.isNull()` is "has no member 'isNull'".
  @Test
  func nullChecksRenderTheIsOperator() {
    #expect(rendered(Todo.columns.dueDate.isNull()) == "due_at=is.null")
    #expect(rendered(!Todo.columns.dueDate.isNull()) == "due_at=not.is.null")
  }

  /// `is.true` is not `eq.true` on a nullable boolean, so all three values are needed.
  @Test
  func booleanIsChecksRenderTheIsOperator() {
    #expect(rendered(Todo.columns.isDone.isTrue()) == "is_done=is.true")
    #expect(rendered(Todo.columns.isDone.isFalse()) == "is_done=is.false")
    #expect(rendered(!Todo.columns.isDone.isTrue()) == "is_done=not.is.true")
  }

  /// A nullable column takes the same operators, against a non-optional operand. `nil` must
  /// never reach one: on a `text` column `col=eq.null` matches the literal string `'null'`.
  @Test
  func aNullableColumnComparesAgainstANonOptionalValue() {
    let when = Date(timeIntervalSince1970: 0)
    let c = Todo.columns
    #expect(rendered(c.dueDate.eq(when)).hasPrefix("due_at=eq."))
    #expect(rendered(c.dueDate.neq(when)).hasPrefix("due_at=neq."))
    #expect(rendered(c.dueDate.gt(when)).hasPrefix("due_at=gt."))
    #expect(rendered(c.dueDate.gte(when)).hasPrefix("due_at=gte."))
    #expect(rendered(c.dueDate.lt(when)).hasPrefix("due_at=lt."))
    #expect(rendered(c.dueDate.lte(when)).hasPrefix("due_at=lte."))
    #expect(rendered(c.dueDate.isDistinct(when)).hasPrefix("due_at=isdistinct."))
  }

  @Test
  func rawAppliesAnUnknownOperatorToACheckedColumn() {
    #expect(rendered(Todo.columns.id.raw("someop.7")) == "id=someop.7")
    #expect(rendered(!Todo.columns.id.raw("someop.7")) == "id=not.someop.7")
  }

  @Test
  func comparisonsComposeWithTheOperators() {
    let c = Todo.columns
    #expect(
      rendered((c.isDone.eq(false) && c.id.gt(3)) || c.id.eq(7))
        == "or=(and(is_done.eq.false,id.gt.3),id.eq.7)")
  }
}
