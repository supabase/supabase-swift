//
//  TableMacroTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 21/08/26.
//

import MacroTesting
import Testing

@testable import PostgrestMacrosPlugin

/// `MacroTesting` expands the macro without its declaration, so `conformingTo:` is always empty
/// here and the recorded extensions carry no inheritance clause. `TableMacroSupportTests` asserts
/// the clause directly.
@Suite(.macros(["Table": TableMacro.self]))
struct TableMacroTests {
  @Test
  func expandsAWritableTable() {
    assertMacro {
      """
      @Table("todos")
      struct Todo {
        @PrimaryKey var id: Int
        var task: String
        @Default var isDone: Bool
        @Column("due_at") var dueDate: Date?
      }
      """
    } expansion: {
      #"""
      struct Todo {
        @PrimaryKey var id: Int
        var task: String
        @Default var isDone: Bool
        @Column("due_at") var dueDate: Date?
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
          case \Self.isDone:
            return "is_done"
          case \Self.dueDate:
            return "due_at"
          default:
            fatalError("Todo: no column is mapped for that key path")
          }
        }

        enum CodingKeys: String, CodingKey {
          case id = "id"
          case task = "task"
          case isDone = "is_done"
          case dueDate = "due_at"
        }

        struct Insert: Encodable, Sendable {
          var task: String
          var isDone: Bool?
          var dueDate: Date?

          enum CodingKeys: String, CodingKey {
            case task = "task"
            case isDone = "is_done"
            case dueDate = "due_at"
          }

          init(task: String, isDone: Bool? = nil, dueDate: Date? = nil) {
            self.task = task
            self.isDone = isDone
            self.dueDate = dueDate
          }
        }

        struct Update: Encodable, Sendable {
          var task: String?
          var isDone: Bool?
          var dueDate: Date?

          enum CodingKeys: String, CodingKey {
            case task = "task"
            case isDone = "is_done"
            case dueDate = "due_at"
          }

          init(task: String? = nil, isDone: Bool? = nil, dueDate: Date? = nil) {
            self.task = task
            self.isDone = isDone
            self.dueDate = dueDate
          }
        }
      }
      """#
    }
  }

  @Test
  func readOnlyTableOmitsInsertAndUpdate() {
    assertMacro {
      """
      @Table("active_todos", readOnly: true)
      struct ActiveTodo {
        var id: Int
      }
      """
    } expansion: {
      #"""
      struct ActiveTodo {
        var id: Int
      }

      extension ActiveTodo {
        static let relationName = "active_todos"

        static let schema = "public"

        static let selectString = "*"

        static func columnName<V>(for keyPath: KeyPath<Self, V>) -> String {
          switch keyPath {
          case \Self.id:
            return "id"
          default:
            fatalError("ActiveTodo: no column is mapped for that key path")
          }
        }

        enum CodingKeys: String, CodingKey {
          case id = "id"
        }
      }
      """#
    }
  }

  @Test
  func propagatesTheAccessLevel() {
    assertMacro {
      """
      @Table("todos", schema: "app")
      public struct Todo {
        @PrimaryKey var id: Int
        var task: String
      }
      """
    } expansion: {
      #"""
      public struct Todo {
        @PrimaryKey var id: Int
        var task: String
      }

      extension Todo {
        public static let relationName = "todos"

        public static let schema = "app"

        public static let selectString = "*"

        public static func columnName<V>(for keyPath: KeyPath<Self, V>) -> String {
          switch keyPath {
          case \Self.id:
            return "id"
          case \Self.task:
            return "task"
          default:
            fatalError("Todo: no column is mapped for that key path")
          }
        }

        enum CodingKeys: String, CodingKey {
          case id = "id"
          case task = "task"
        }

        public struct Insert: Encodable, Sendable {
          public var task: String

          enum CodingKeys: String, CodingKey {
            case task = "task"
          }

          public init(task: String) {
            self.task = task
          }
        }

        public struct Update: Encodable, Sendable {
          public var task: String?

          enum CodingKeys: String, CodingKey {
            case task = "task"
          }

          public init(task: String? = nil) {
            self.task = task
          }
        }
      }
      """#
    }
  }

  @Test
  func skipsComputedAndStaticMembers() {
    assertMacro {
      """
      @Table("todos")
      struct Todo {
        static let table = "todos"
        var htmlURL: String
        var summary: String { htmlURL }
      }
      """
    } expansion: {
      #"""
      struct Todo {
        static let table = "todos"
        var htmlURL: String
        var summary: String { htmlURL }
      }

      extension Todo {
        static let relationName = "todos"

        static let schema = "public"

        static let selectString = "*"

        static func columnName<V>(for keyPath: KeyPath<Self, V>) -> String {
          switch keyPath {
          case \Self.htmlURL:
            return "html_url"
          default:
            fatalError("Todo: no column is mapped for that key path")
          }
        }

        enum CodingKeys: String, CodingKey {
          case htmlURL = "html_url"
        }

        struct Insert: Encodable, Sendable {
          var htmlURL: String

          enum CodingKeys: String, CodingKey {
            case htmlURL = "html_url"
          }

          init(htmlURL: String) {
            self.htmlURL = htmlURL
          }
        }

        struct Update: Encodable, Sendable {
          var htmlURL: String?

          enum CodingKeys: String, CodingKey {
            case htmlURL = "html_url"
          }

          init(htmlURL: String? = nil) {
            self.htmlURL = htmlURL
          }
        }
      }
      """#
    }
  }
  @Test
  func coversEveryBindingInAMultiBindingDeclaration() {
    assertMacro {
      """
      @Table("todos")
      struct Todo {
        @PrimaryKey var id: Int
        var task: String, note: String
        var draft, review: String
      }
      """
    } expansion: {
      #"""
      struct Todo {
        @PrimaryKey var id: Int
        var task: String, note: String
        var draft, review: String
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
          case \Self.note:
            return "note"
          case \Self.draft:
            return "draft"
          case \Self.review:
            return "review"
          default:
            fatalError("Todo: no column is mapped for that key path")
          }
        }

        enum CodingKeys: String, CodingKey {
          case id = "id"
          case task = "task"
          case note = "note"
          case draft = "draft"
          case review = "review"
        }

        struct Insert: Encodable, Sendable {
          var task: String
          var note: String
          var draft: String
          var review: String

          enum CodingKeys: String, CodingKey {
            case task = "task"
            case note = "note"
            case draft = "draft"
            case review = "review"
          }

          init(task: String, note: String, draft: String, review: String) {
            self.task = task
            self.note = note
            self.draft = draft
            self.review = review
          }
        }

        struct Update: Encodable, Sendable {
          var task: String?
          var note: String?
          var draft: String?
          var review: String?

          enum CodingKeys: String, CodingKey {
            case task = "task"
            case note = "note"
            case draft = "draft"
            case review = "review"
          }

          init(task: String? = nil, note: String? = nil, draft: String? = nil, review: String? = nil) {
            self.task = task
            self.note = note
            self.draft = draft
            self.review = review
          }
        }
      }
      """#
    }
  }

  @Test
  func includesAStoredPropertyWithObservers() {
    assertMacro {
      """
      @Table("todos")
      struct Todo {
        @PrimaryKey var id: Int
        var task: String = "" {
          didSet { print(task) }
        }
        var count: Int {
          task.count
        }
      }
      """
    } expansion: {
      #"""
      struct Todo {
        @PrimaryKey var id: Int
        var task: String = "" {
          didSet { print(task) }
        }
        var count: Int {
          task.count
        }
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

        enum CodingKeys: String, CodingKey {
          case id = "id"
          case task = "task"
        }

        struct Insert: Encodable, Sendable {
          var task: String

          enum CodingKeys: String, CodingKey {
            case task = "task"
          }

          init(task: String) {
            self.task = task
          }
        }

        struct Update: Encodable, Sendable {
          var task: String?

          enum CodingKeys: String, CodingKey {
            case task = "task"
          }

          init(task: String? = nil) {
            self.task = task
          }
        }
      }
      """#
    }
  }

  @Test
  func doesNotBorrowATypeAnnotationForAnInitializedBinding() {
    // `count` is an `Int` inferred from its initializer, not the `String` that `label` declares.
    // Reading forward for a shared annotation is only correct for a binding that has no
    // initializer of its own, so `count` is skipped rather than typed `String`.
    //
    // Skipping is the pre-existing behavior for any property whose type comes from an initializer
    // (`var isDone = false`). It means the property silently gets no column, which wants a
    // diagnostic — see the note in `postgrestStoredProperties()`.
    assertMacro {
      """
      @Table("todos")
      struct Todo {
        @PrimaryKey var id: Int
        var count = 1, label: String
      }
      """
    } expansion: {
      #"""
      struct Todo {
        @PrimaryKey var id: Int
        var count = 1, label: String
      }

      extension Todo {
        static let relationName = "todos"

        static let schema = "public"

        static let selectString = "*"

        static func columnName<V>(for keyPath: KeyPath<Self, V>) -> String {
          switch keyPath {
          case \Self.id:
            return "id"
          case \Self.label:
            return "label"
          default:
            fatalError("Todo: no column is mapped for that key path")
          }
        }

        enum CodingKeys: String, CodingKey {
          case id = "id"
          case label = "label"
        }

        struct Insert: Encodable, Sendable {
          var label: String

          enum CodingKeys: String, CodingKey {
            case label = "label"
          }

          init(label: String) {
            self.label = label
          }
        }

        struct Update: Encodable, Sendable {
          var label: String?

          enum CodingKeys: String, CodingKey {
            case label = "label"
          }

          init(label: String? = nil) {
            self.label = label
          }
        }
      }
      """#
    }
  }

}
