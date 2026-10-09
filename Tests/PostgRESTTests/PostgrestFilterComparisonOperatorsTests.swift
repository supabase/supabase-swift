//
//  PostgrestFilterComparisonOperatorsTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 09/10/26.
//

import Foundation
import Testing

@_spi(Experimental) @testable import PostgREST

@Suite
struct PostgrestFilterComparisonOperatorsTests {
  struct Todo: _PostgrestRelation {
    static let relationName = "todos"
    static let selectString = "*"

    var id: Int
    var done: Bool
    var priority: Int
    var pinned: Bool
    var title: String
    var dueDate: Date?

    struct Columns: Sendable {
      let id = _PostgrestColumn<Todo, Int>("id")
      let done = _PostgrestColumn<Todo, Bool>("done")
      let priority = _PostgrestColumn<Todo, Int>("priority")
      let pinned = _PostgrestColumn<Todo, Bool>("pinned")
      let title = _PostgrestColumn<Todo, String>("title")
      let dueDate = _PostgrestNullableColumn<Todo, Date>("due_at")
    }

    static let columns = Columns()
  }

  private func rendered(_ filter: _PostgrestFilter<Todo>) -> String {
    filter.queryItems().map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&")
  }

  /// The rows of the design spec's §4.3 table, each in both spellings.
  @Test
  func operatorAndMethodSpellingsRenderTheSame() {
    let c = Todo.columns
    let rows:
      [(operators: _PostgrestFilter<Todo>, methods: _PostgrestFilter<Todo>, expected: String)] = [
        (
          c.done == false && c.priority > 3,
          c.done.eq(false) && c.priority.gt(3),
          "done=eq.false&priority=gt.3"
        ),
        (
          c.done == false || c.priority > 3,
          c.done.eq(false) || c.priority.gt(3),
          "or=(done.eq.false,priority.gt.3)"
        ),
        (
          (c.done == false && c.priority > 3) || c.pinned == true,
          (c.done.eq(false) && c.priority.gt(3)) || c.pinned.eq(true),
          "or=(and(done.eq.false,priority.gt.3),pinned.eq.true)"
        ),
        (
          !(c.done == false && c.priority > 3),
          !(c.done.eq(false) && c.priority.gt(3)),
          "not.and=(done.eq.false,priority.gt.3)"
        ),
      ]
    for row in rows {
      #expect(rendered(row.operators) == row.expected)
      #expect(rendered(row.methods) == row.expected)
    }
  }

  @Test
  func everyComparisonOperatorMatchesItsMethod() {
    let c = Todo.columns
    #expect(rendered(c.title == "a") == rendered(c.title.eq("a")))
    #expect(rendered(c.title != "a") == rendered(c.title.neq("a")))
    #expect(rendered(c.id < 3) == rendered(c.id.lt(3)))
    #expect(rendered(c.id <= 3) == rendered(c.id.lte(3)))
    #expect(rendered(c.id > 3) == rendered(c.id.gt(3)))
    #expect(rendered(c.id >= 3) == rendered(c.id.gte(3)))
    #expect(rendered(c.id >= 3) == "id=gte.3")
  }

  /// `eq.null` on a `text` column matches the string `'null'`, not the `NULL` row, so `== nil`
  /// must render `is.null`. `c.dueDate.eq(nil)` and `c.id == nil` (a `NOT NULL` column) do not
  /// compile.
  @Test
  func comparingWithNilRendersTheIsOperator() {
    let c = Todo.columns
    #expect(rendered(c.dueDate == nil) == "due_at=is.null")
    #expect(rendered(c.dueDate != nil) == "due_at=not.is.null")
    #expect(rendered(c.dueDate == nil || c.id == 3) == "or=(due_at.is.null,id.eq.3)")
  }

  @Test
  func operatorsWorkInsideWhere() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from(Todo.self)
      .select()
      .where { $0.priority > 3 || $0.dueDate == nil }
      .execute()
    #expect(capture.query?.contains("or=(priority.gt.3,due_at.is.null)") == true)
  }
}
