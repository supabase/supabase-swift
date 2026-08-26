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

  @Test
  func tableRejectsAPropertyWithNoTypeAnnotation() {
    // Left alone, the property has a default, so `Decodable` synthesis still succeeds. The column
    // never round-trips and the mistake surfaces only when `columnName(for:)` traps at runtime.
    assertMacro {
      """
      @Table("todos")
      struct Todo {
        @PrimaryKey var id: Int
        var isDone = false
      }
      """
    } diagnostics: {
      """
      @Table("todos")
      struct Todo {
        @PrimaryKey var id: Int
        var isDone = false
            ┬─────
            ╰─ 🛑 @Table requires an explicit type annotation on 'isDone', as in 'var isDone: <Type> = ...' — without one the macro cannot infer the type, and the column is dropped
      }
      """
    }
  }

  @Test
  func tableReportsEveryPropertyWithNoTypeAnnotation() {
    // One diagnostic per property, so the author fixes them all in one pass.
    assertMacro {
      """
      @Table("todos")
      struct Todo {
        @PrimaryKey var id: Int
        var isDone = false
        var task = ""
      }
      """
    } diagnostics: {
      """
      @Table("todos")
      struct Todo {
        @PrimaryKey var id: Int
        var isDone = false
            ┬─────
            ╰─ 🛑 @Table requires an explicit type annotation on 'isDone', as in 'var isDone: <Type> = ...' — without one the macro cannot infer the type, and the column is dropped
        var task = ""
            ┬───
            ╰─ 🛑 @Table requires an explicit type annotation on 'task', as in 'var task: <Type> = ...' — without one the macro cannot infer the type, and the column is dropped
      }
      """
    }
  }

  @Test
  func tableAcceptsMembersThatMapToNoColumn() {
    // A static member and a computed property are not stored, so neither maps to a column and
    // neither is a missing annotation.
    assertMacro {
      """
      @Table("todos")
      struct Todo {
        @PrimaryKey var id: Int
        var task: String
        static let placeholder = "none"
        var summary: String { "todo" }
      }
      """
    } expansion: {
      #"""
      struct Todo {
        @PrimaryKey var id: Int
        var task: String
        static let placeholder = "none"
        var summary: String { "todo" }
      }

      extension Todo {
        static let relationName = "todos"

        static let schema = "public"

        static let selectString = "*"

        static func columnName<V>(for keyPath: KeyPath<Self, V>) -> String {
          switch keyPath {
          case \Self.id:
            return "id"
          case \Self.task:
            return "task"
          default:
            fatalError("Todo: no column is mapped for that key path")
          }
        }

        static let primaryKeyColumns: [String] = ["id"]

        enum CodingKeys: String, CodingKey {
          case id = "id"
          case task = "task"
        }

        struct Insert: Encodable, Sendable {
          var id: Int
          var task: String

          enum CodingKeys: String, CodingKey {
            case id = "id"
            case task = "task"
          }

          init(id: Int, task: String) {
            self.id = id
            self.task = task
          }
        }
      }
      """#
    }
  }

  @Test
  func selectionOfRejectsAPropertyWithNoTypeAnnotation() {
    assertMacro {
      """
      @SelectionOf(Todo.self)
      struct TodoSummary {
        var id: Int
        var isDone = false
      }
      """
    } diagnostics: {
      """
      @SelectionOf(Todo.self)
      struct TodoSummary {
        var id: Int
        var isDone = false
            ┬─────
            ╰─ 🛑 @SelectionOf requires an explicit type annotation on 'isDone', as in 'var isDone: <Type> = ...' — without one the macro cannot infer the type, and the column is dropped
      }
      """
    }
  }

  @Test
  func tableRejectsABindingThatCannotBorrowAnAnnotation() {
    // `count` is an `Int` from its initializer, not the `String` that `label` declares, so
    // `postgrestType(at:)` refuses to read `label`'s annotation forward and leaves `count`
    // untyped. `label` itself is fine, so only `count` is reported.
    assertMacro {
      """
      @Table("todos")
      struct Todo {
        @PrimaryKey var id: Int
        var count = 1, label: String
      }
      """
    } diagnostics: {
      """
      @Table("todos")
      struct Todo {
        @PrimaryKey var id: Int
        var count = 1, label: String
            ┬────
            ╰─ 🛑 @Table requires an explicit type annotation on 'count', as in 'var count: <Type> = ...' — without one the macro cannot infer the type, and the column is dropped
      }
      """
    }
  }
}
