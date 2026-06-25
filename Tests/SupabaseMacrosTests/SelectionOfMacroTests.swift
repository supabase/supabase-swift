import MacroTesting
import XCTest

@testable import SupabaseMacros

final class SelectionOfMacroTests: XCTestCase {
  override func invokeTest() {
    withMacroTesting(
      macros: [
        "SelectionOf": SelectionOfMacro.self,
        "Column": ColumnMacro.self,
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

  func testNestedRelationship() {
    assertMacro {
      """
      @SelectionOf(Todo.self)
      public struct TodoWithProfile {
        public let id: UUID
        public let profile: Profile
      }
      """
    } expansion: {
      #"""
      public struct TodoWithProfile {
        public let id: UUID
        public let profile: Profile

        public enum CodingKeys: String, CodingKey {
          case id
          case profile
        }
      }

      extension TodoWithProfile: SelectionRepresentable {
        public static var selectString: String {
          var parts: [String] = []
          parts.append("id")
          parts.append("profile(\(Profile.selectString))")
          return parts.joined(separator: ",")
        }
      }
      """#
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
