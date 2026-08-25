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
  func keepsObservedStoredProperties() {
    // `willSet`/`didSet` put an accessor block on a property that still holds a value, so it still
    // needs its column.
    assertMacro {
      """
      @Table("todos")
      struct Todo {
        @PrimaryKey var id: Int
        var isDone: Bool = false { didSet { print(isDone) } }
        var task: String { willSet { print(newValue) } }
      }
      """
    } expansion: {
      #"""
      struct Todo {
        @PrimaryKey var id: Int
        var isDone: Bool = false { didSet { print(isDone) } }
        var task: String { willSet { print(newValue) } }
      }

      extension Todo {
        static let relationName = "todos"

        static let schema = "public"

        static let selectString = "*"

        static func columnName<V>(for keyPath: KeyPath<Self, V>) -> String {
          switch keyPath {
          case \Self.id:
            return "id"
          case \Self.isDone:
            return "is_done"
          case \Self.task:
            return "task"
          default:
            fatalError("Todo: no column is mapped for that key path")
          }
        }

        enum CodingKeys: String, CodingKey {
          case id = "id"
          case isDone = "is_done"
          case task = "task"
        }

        struct Insert: Encodable, Sendable {
          var isDone: Bool
          var task: String

          enum CodingKeys: String, CodingKey {
            case isDone = "is_done"
            case task = "task"
          }

          init(isDone: Bool, task: String) {
            self.isDone = isDone
            self.task = task
          }
        }

        struct Update: Encodable, Sendable {
          var isDone: Bool?
          var task: String?

          enum CodingKeys: String, CodingKey {
            case isDone = "is_done"
            case task = "task"
          }

          init(isDone: Bool? = nil, task: String? = nil) {
            self.isDone = isDone
            self.task = task
          }
        }
      }
      """#
    }
  }

  @Test
  func skipsPropertiesThatComputeTheirValue() {
    // Every accessor block that is not observers-only: an explicit getter, a getter with a setter,
    // and a `_read` coroutine. None holds a value, so none maps to a column.
    assertMacro {
      """
      @Table("todos")
      struct Todo {
        var task: String
        var upper: String { get { task } }
        var settable: String { get { task } set { task = newValue } }
        var yielded: String { _read { yield task } }
      }
      """
    } expansion: {
      #"""
      struct Todo {
        var task: String
        var upper: String { get { task } }
        var settable: String { get { task } set { task = newValue } }
        var yielded: String { _read { yield task } }
      }

      extension Todo {
        static let relationName = "todos"

        static let schema = "public"

        static let selectString = "*"

        static func columnName<V>(for keyPath: KeyPath<Self, V>) -> String {
          switch keyPath {
          case \Self.task:
            return "task"
          default:
            fatalError("Todo: no column is mapped for that key path")
          }
        }

        enum CodingKeys: String, CodingKey {
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
}
