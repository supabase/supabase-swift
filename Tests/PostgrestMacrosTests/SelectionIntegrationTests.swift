//
//  SelectionIntegrationTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 21/08/26.
//

import Foundation
import PostgrestMacros
import Testing

// File scope, for the same reason as `TableIntegrationTests`: `@Table` and `@SelectionOf` both
// attach extensions, which cannot be nested inside another type.
@Table("todos")
struct SelectionTodo {
  @PrimaryKey var id: Int
  var task: String
  @Default var isDone: Bool
  @Column("due_at") var dueDate: Date?
}

@SelectionOf(SelectionTodo.self)
struct SelectionTodoSummary: Hashable {
  var id: Int
  var isDone: Bool
}

@SelectionOf(SelectionTodo.self)
struct SelectionTodoDueDate {
  @Column("due_at") var dueDate: Date?
}

/// The same property, without repeating the relation's `@Column`.
@SelectionOf(SelectionTodo.self)
struct SelectionTodoInheritedColumn {
  var dueDate: Date?
}

@Suite
struct SelectionIntegrationTests {
  typealias TodoSummary = SelectionTodoSummary

  @Test
  func selectStringListsTheDeclaredColumns() {
    // Each entry is a PostgREST alias, `key:column`. The column comes from the relation; the key
    // is what the response is returned under, and it is what `CodingKeys` decodes. Here the two
    // agree, so the alias is a no-op.
    #expect(TodoSummary.selectString == "id:id,is_done:is_done")
  }

  @Test
  func columnOverridesApply() {
    #expect(SelectionTodoDueDate.selectString == "due_at:due_at")
  }

  @Test
  func aSelectionInheritsTheRelationsColumnMapping() {
    // The regression this guards: `dueDate` snake-cases to `due_date`, but the relation maps it to
    // `due_at`. Deriving the column locally asked PostgREST for a column that does not exist, and
    // nothing caught it — `_columnCheck` proves the key path resolves, not that the name matches.
    // Reading the column from the relation makes repeating `@Column` on a selection unnecessary.
    #expect(SelectionTodoInheritedColumn.selectString == "due_date:due_at")
  }

  @Test
  func aSelectionNamesItsSource() {
    // `select(_:)` is gated on this, so a selection cannot be handed to another relation.
    #expect(TodoSummary.Source.relationName == "todos")
  }

  @Test
  func aRelationIsItsOwnSource() {
    #expect(SelectionTodo.Source.relationName == "todos")
  }

  @Test
  func selectSendsTheSelectStringAndDecodesTheSelection() async throws {
    let capture = RequestCapture(body: #"[{"id":1,"is_done":false}]"#)
    let rows = try await capture.client
      .from(SelectionTodo.self)
      .select(TodoSummary.self)
      .eq(\.isDone, false)
      .execute()
      .value

    #expect(rows == [TodoSummary(id: 1, isDone: false)])
    #expect(capture.path?.hasSuffix("/todos") == true)
    // `RequestCapture.query` is the decoded query, so the aliases read as written here. On the
    // wire the `:` and `,` are escaped.
    #expect(capture.query?.contains("select=id:id,is_done:is_done") == true)
    #expect(capture.query?.contains("is_done=eq.false") == true)
  }
}
