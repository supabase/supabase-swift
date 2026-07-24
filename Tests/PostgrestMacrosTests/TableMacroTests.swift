import MacroTesting
import XCTest

@testable import PostgrestMacrosPlugin

final class TableMacroTests: XCTestCase {
  override func invokeTest() {
    withMacroTesting(
      macros: [
        "Table": TableMacro.self,
        "PrimaryKey": PrimaryKeyMacro.self,
        "Default": DefaultMacro.self,
        "Column": ColumnMacro.self,
        "Relationship": RelationshipMacro.self,
      ]
    ) { super.invokeTest() }
  }

  func testFullTableExpansion() {
    assertMacro {
      """
      @Table("todos")
      public struct Todo {
        @PrimaryKey public var id: UUID
        public var title: String
        @Default public var isComplete: Bool
        @Column("user_id") public var userId: UUID
      }
      """
    } expansion: {
      #"""
      public struct Todo {
        public var id: UUID
        public var title: String
        public var isComplete: Bool
        public var userId: UUID

        public static let tableName: String = "todos"

        public static let schema: String = "public"

        public static let selectString: String = "*"

        public static func columnName<V>(for keyPath: KeyPath<Todo, V>) -> String {
          let erased = keyPath as AnyKeyPath
          if erased == \Todo.id {
            return "id"
          }
          if erased == \Todo.title {
            return "title"
          }
          if erased == \Todo.isComplete {
            return "is_complete"
          }
          if erased == \Todo.userId {
            return "user_id"
          }
          preconditionFailure("Unknown column keypath on Todo — macro bug")
        }

        public struct Insert: Encodable {
          public var title: String
          public var isComplete: Bool? = nil
          public var userId: UUID
          public enum CodingKeys: String, CodingKey {
              case title
              case isComplete = "is_complete"
              case userId = "user_id"
          }
        }

        public struct Update: Encodable {
          public var title: String? = nil
          public var isComplete: Bool? = nil
          public var userId: UUID? = nil
          public enum CodingKeys: String, CodingKey {
              case title
              case isComplete = "is_complete"
              case userId = "user_id"
          }
        }

        public enum CodingKeys: String, CodingKey {
            case id
            case title
            case isComplete = "is_complete"
            case userId = "user_id"
        }
      }
      """#
    }
  }

  func testRelationshipOnTableDiagnostic() {
    assertMacro {
      #"""
      @Table("todos")
      public struct Todo {
        @PrimaryKey public var id: UUID
        @Relationship(\Profile.userId) public var profile: Profile?
      }
      """#
    } diagnostics: {
      #"""
      @Table("todos")
      public struct Todo {
        @PrimaryKey public var id: UUID
        @Relationship(\Profile.userId) public var profile: Profile?
        ┬─────────────────────────────
        ╰─ 🛑 '@Relationship' fields are not allowed in '@Table'. Declare a '@SelectionOf' struct to join related tables.
      }
      """#
    }
  }

  func testReadOnlyTableExpansion() {
    assertMacro {
      """
      @Table("todo_stats", readOnly: true)
      public struct TodoStats {
        public var userId: UUID
        public var totalCount: Int
      }
      """
    } expansion: {
      #"""
      public struct TodoStats {
        public var userId: UUID
        public var totalCount: Int

        public static let tableName: String = "todo_stats"

        public static let schema: String = "public"

        public static let selectString: String = "*"

        public static func columnName<V>(for keyPath: KeyPath<TodoStats, V>) -> String {
          let erased = keyPath as AnyKeyPath
          if erased == \TodoStats.userId {
            return "user_id"
          }
          if erased == \TodoStats.totalCount {
            return "total_count"
          }
          preconditionFailure("Unknown column keypath on TodoStats — macro bug")
        }

        public enum CodingKeys: String, CodingKey {
            case userId = "user_id"
            case totalCount = "total_count"
        }
      }
      """#
    }
  }

  func testLetBindingDiagnostic() {
    assertMacro {
      """
      @Table("todos")
      public struct Todo {
        @PrimaryKey public let id: UUID
        public let title: String
      }
      """
    } diagnostics: {
      """
      @Table("todos")
      public struct Todo {
        @PrimaryKey public let id: UUID
        ┬──────────────────────────────
        ╰─ 🛑 @Table requires stored properties to use 'var', not 'let'
        public let title: String
        ┬───────────────────────
        ╰─ 🛑 @Table requires stored properties to use 'var', not 'let'
      }
      """
    }
  }

  func testNonStructDiagnostic() {
    assertMacro {
      """
      @Table("foo")
      enum Foo {}
      """
    } diagnostics: {
      """
      @Table("foo")
      ┬────────────
      ╰─ 🛑 @Table can only be applied to structs
      enum Foo {}
      """
    }
  }
}
