//
//  DiagnosticsTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 21/08/26.
//

import MacroTesting
import Testing

@testable import PostgrestMacrosPlugin

@Suite(.macros(["Table": TableMacro.self, "SelectionOf": SelectionOfMacro.self]))
struct DiagnosticsTests {
  @Test
  func tableRejectsAClass() {
    assertMacro {
      """
      @Table("todos")
      class Todo {
        var id: Int = 0
      }
      """
    } diagnostics: {
      """
      @Table("todos")
      ┬──────────────
      ╰─ 🛑 @Table can only be applied to a struct
      class Todo {
        var id: Int = 0
      }
      """
    }
  }

  @Test
  func tableRejectsARelationshipProperty() {
    // Forward-looking. `@Relationship` lands in stage 3, so today the compiler rejects the unknown
    // attribute first; `assertMacro` has no such check, which is what lets this be tested now.
    assertMacro {
      """
      @Table("todos")
      struct Todo {
        var id: Int
        @Relationship(\\Comment.todoID) var comments: [Comment]
      }
      """
    } diagnostics: {
      #"""
      @Table("todos")
      struct Todo {
        var id: Int
        @Relationship(\Comment.todoID) var comments: [Comment]
        ┬─────────────────────────────
        ╰─ 🛑 @Relationship belongs on a @SelectionOf type, not on @Table
      }
      """#
    }
  }

  @Test
  func selectionOfRejectsAClass() {
    assertMacro {
      """
      @SelectionOf(Todo.self)
      class TodoSummary {
        var id: Int = 0
      }
      """
    } diagnostics: {
      """
      @SelectionOf(Todo.self)
      ┬──────────────────────
      ╰─ 🛑 @SelectionOf can only be applied to a struct
      class TodoSummary {
        var id: Int = 0
      }
      """
    }
  }

  @Test
  func selectionOfRequiresARelationType() {
    // Bare `@SelectionOf` is what `assertMacro` can express. In real code the compiler catches the
    // missing argument first, and this fires on an argument that is not a `T.self` member access —
    // `@SelectionOf(someTypeVariable)`.
    assertMacro {
      """
      @SelectionOf
      struct TodoSummary {
        var id: Int
      }
      """
    } diagnostics: {
      """
      @SelectionOf
      ┬───────────
      ╰─ 🛑 @SelectionOf requires a relation type, e.g. @SelectionOf(Todo.self)
      struct TodoSummary {
        var id: Int
      }
      """
    }
  }
}
