import MacroTesting
import XCTest

@testable import SupabaseMacros

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
        @Relationship("user_id", references: Profile.self) public var profile: Profile?
      }
      """
    } expansion: {
      #"""
      public struct Todo {
        public var id: UUID
        public var title: String
        public var isComplete: Bool
        public var userId: UUID
        public var profile: Profile?

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
            case profile
        }

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
      }

      extension Todo: TableRepresentable {
        public static let tableName = "todos"
        public static let schema = "public"
        public static let selectString = "*"
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

        public enum CodingKeys: String, CodingKey {
            case userId = "user_id"
            case totalCount = "total_count"
        }

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
      }

      extension TodoStats: ReadOnlyTableRepresentable {
        public static let tableName = "todo_stats"
        public static let schema = "public"
        public static let selectString = "*"
      }
      """#
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
