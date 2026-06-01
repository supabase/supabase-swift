import SwiftSyntaxMacrosTestSupport
import XCTest
@testable import _RealtimeTableMacroPlugin

final class RealtimeTableMacroTests: XCTestCase {
  func testBasicExpansion() throws {
    assertMacroExpansion(
      """
      @RealtimeTable(schema: "public", table: "messages")
      struct Message: Codable, Sendable {
        var id: UUID
        var roomId: UUID
        var text: String
      }
      """,
      expandedSource: """
      struct Message: Codable, Sendable {
        var id: UUID
        var roomId: UUID
        var text: String
      }

      extension Message: RealtimeTable {
        static let schema: String = "public"
        static let tableName: String = "messages"
        static func columnName<V>(for keyPath: KeyPath<Message, V>) -> String {
          switch keyPath {
          case \\Message.id:
              return "id"
          case \\Message.roomId:
              return "room_id"
          case \\Message.text:
              return "text"
          default:
              fatalError("Unknown keypath for RealtimeTable \\(keyPath)")
          }
        }
      }
      """,
      macros: ["RealtimeTable": RealtimeTableMacro.self]
    )
  }

  func testCustomCodingKeysRespected() throws {
    assertMacroExpansion(
      """
      @RealtimeTable(schema: "public", table: "users")
      struct User: Codable, Sendable {
        var id: UUID
        var createdAt: Date

        enum CodingKeys: String, CodingKey {
          case id
          case createdAt = "created_at"
        }
      }
      """,
      expandedSource: """
      struct User: Codable, Sendable {
        var id: UUID
        var createdAt: Date

        enum CodingKeys: String, CodingKey {
          case id
          case createdAt = "created_at"
        }
      }

      extension User: RealtimeTable {
        static let schema: String = "public"
        static let tableName: String = "users"
        static func columnName<V>(for keyPath: KeyPath<User, V>) -> String {
          switch keyPath {
          case \\User.id:
              return "id"
          case \\User.createdAt:
              return "created_at"
          default:
              fatalError("Unknown keypath for RealtimeTable \\(keyPath)")
          }
        }
      }
      """,
      macros: ["RealtimeTable": RealtimeTableMacro.self]
    )
  }
}
