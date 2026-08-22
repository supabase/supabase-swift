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

@Suite
struct SelectionIntegrationTests {
  typealias TodoSummary = SelectionTodoSummary

  @Test
  func selectStringListsTheDeclaredColumns() {
    #expect(TodoSummary.selectString == "id,is_done")
  }

  @Test
  func columnOverridesApply() {
    #expect(SelectionTodoDueDate.selectString == "due_at")
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
    #expect(capture.query?.contains("select=id,is_done") == true)
    #expect(capture.query?.contains("is_done=eq.false") == true)
  }
}
