import MacroTesting
import XCTest

@testable import SupabaseMacros

final class SelectionOfMacroTests: XCTestCase {
  override func invokeTest() {
    withMacroTesting(
      macros: [
        "SelectionOf": SelectionOfMacro.self,
        "Column": ColumnMacro.self,
        "Relationship": RelationshipMacro.self,
      ]
    ) { super.invokeTest() }
  }

  func testBasicProjection() {
    assertMacro {
      """
      @SelectionOf(Todo.self)
      public struct TodoSummary {
        public let id: UUID
        public let title: String
      }
      """
    } expansion: {
      """
      public struct TodoSummary {
        public let id: UUID
        public let title: String

        public enum CodingKeys: String, CodingKey {
          case id
          case title
        }
      }

      extension TodoSummary: SelectionRepresentable {
        public static var selectString: String {
          var parts: [String] = []
          parts.append("id")
          parts.append("title")
          return parts.joined(separator: ",")
        }
      }
      """
    }
  }

  // Old testNestedRelationship: non-primitive without @Relationship is now an error
  func testNestedRelationship() {
    assertMacro {
      """
      @SelectionOf(Todo.self)
      public struct TodoWithProfile {
        public let id: UUID
        public let profile: Profile
      }
      """
    } diagnostics: {
      """
      @SelectionOf(Todo.self)
      public struct TodoWithProfile {
        public let id: UUID
        public let profile: Profile
        ┬──────────────────────────
        ╰─ 🛑 Embedded type 'Profile' in '@SelectionOf' requires '@Relationship'
      }
      """
    }
  }

  func testRelationshipDisambiguationString() {
    assertMacro {
      #"""
      @SelectionOf(Message.self)
      public struct MessageWithSender {
        public var id: UUID
        public var body: String
        @Relationship(\Message.senderId) public var sender: User
      }
      """#
    } expansion: {
      #"""
      public struct MessageWithSender {
        public var id: UUID
        public var body: String
        public var sender: User

        public enum CodingKeys: String, CodingKey {
          case id
          case body
          case sender
        }
      }

      extension MessageWithSender: SelectionRepresentable {
        public static var selectString: String {
          var parts: [String] = []
          parts.append("id")
          parts.append("body")
          parts.append("sender:\(User.tableName)!\(Message.columnName(for: \.senderId))(\(User.selectString))")
          return parts.joined(separator: ",")
        }
      }
      """#
    }
  }

  func testRelationshipOptional() {
    assertMacro {
      #"""
      @SelectionOf(Message.self)
      public struct MessageView {
        public var id: UUID
        @Relationship(\Message.senderId) public var sender: User?
      }
      """#
    } expansion: {
      #"""
      public struct MessageView {
        public var id: UUID
        public var sender: User?

        public enum CodingKeys: String, CodingKey {
          case id
          case sender
        }
      }

      extension MessageView: SelectionRepresentable {
        public static var selectString: String {
          var parts: [String] = []
          parts.append("id")
          parts.append("sender:\(User.tableName)!\(Message.columnName(for: \.senderId))(\(User.selectString))")
          return parts.joined(separator: ",")
        }
      }
      """#
    }
  }

  func testRelationshipArray() {
    assertMacro {
      #"""
      @SelectionOf(User.self)
      public struct UserWithTodos {
        public var id: UUID
        @Relationship(\Todo.userId) public var todos: [Todo]
      }
      """#
    } expansion: {
      #"""
      public struct UserWithTodos {
        public var id: UUID
        public var todos: [Todo]

        public enum CodingKeys: String, CodingKey {
          case id
          case todos
        }
      }

      extension UserWithTodos: SelectionRepresentable {
        public static var selectString: String {
          var parts: [String] = []
          parts.append("id")
          parts.append("todos:\(Todo.tableName)!\(Todo.columnName(for: \.userId))(\(Todo.selectString))")
          return parts.joined(separator: ",")
        }
      }
      """#
    }
  }

  func testMultipleRelationships() {
    assertMacro {
      #"""
      @SelectionOf(Message.self)
      public struct MessageWithParticipants {
        public var id: UUID
        @Relationship(\Message.senderId) public var sender: User
        @Relationship(\Message.receiverId) public var receiver: User
      }
      """#
    } expansion: {
      #"""
      public struct MessageWithParticipants {
        public var id: UUID
        public var sender: User
        public var receiver: User

        public enum CodingKeys: String, CodingKey {
          case id
          case sender
          case receiver
        }
      }

      extension MessageWithParticipants: SelectionRepresentable {
        public static var selectString: String {
          var parts: [String] = []
          parts.append("id")
          parts.append("sender:\(User.tableName)!\(Message.columnName(for: \.senderId))(\(User.selectString))")
          parts.append("receiver:\(User.tableName)!\(Message.columnName(for: \.receiverId))(\(User.selectString))")
          return parts.joined(separator: ",")
        }
      }
      """#
    }
  }

  func testNonPrimitiveWithoutRelationshipDiagnostic() {
    assertMacro {
      """
      @SelectionOf(Message.self)
      public struct MessageView {
        public var id: UUID
        public var sender: User
      }
      """
    } diagnostics: {
      """
      @SelectionOf(Message.self)
      public struct MessageView {
        public var id: UUID
        public var sender: User
        ┬──────────────────────
        ╰─ 🛑 Embedded type 'User' in '@SelectionOf' requires '@Relationship'
      }
      """
    }
  }

  func testColumnAnnotationOverridesSnakeCase() {
    assertMacro {
      """
      @SelectionOf(Todo.self)
      public struct TodoUserId {
        public let id: UUID
        @Column("user_id") public let userId: UUID
      }
      """
    } expansion: {
      """
      public struct TodoUserId {
        public let id: UUID
        public let userId: UUID

        public enum CodingKeys: String, CodingKey {
          case id
          case userId = "user_id"
        }
      }

      extension TodoUserId: SelectionRepresentable {
        public static var selectString: String {
          var parts: [String] = []
          parts.append("id")
          parts.append("user_id")
          return parts.joined(separator: ",")
        }
      }
      """
    }
  }
}
