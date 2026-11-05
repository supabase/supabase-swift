import Foundation
import IdentifiedCollections
@_spi(Experimental) import Supabase

nonisolated struct Todo: Identifiable, Hashable, Decodable {
  let id: UUID
  var description: String
  var isComplete: Bool
  let createdAt: Date

  enum CodingKeys: String, CodingKey {
    case id
    case description
    case isComplete = "is_complete"
    case createdAt = "created_at"
  }
}

// What `@Table("todos")` would generate, written by hand: the types the macro generates take this
// target's main-actor default isolation, which fails to build on Xcode 26.
nonisolated extension Todo: _PostgrestKeyedRelation {
  static let relationName = "todos"
  static let selectString = "id,description,is_complete,created_at"
  static let primaryKeyColumns = ["id"]

  struct Columns: Sendable {}
  static let columns = Columns()
}

extension IdentifiedArrayOf<Todo> {
  static func fetchTodos() async throws -> Self {
    let todos: [Todo] = try await supabase.from("todos")
      .select()
      .order("created_at", ascending: false)
      .execute()
      .value
    return Self(uniqueElements: todos)
  }

  /// Applies one change. A change for a row the list already holds replaces it, because a fetch
  /// and the stream can both report the same row.
  mutating func apply(_ change: TypedPostgresChange<Todo>) throws {
    switch change.kind {
    case .insert, .update:
      updateOrInsert(try change.row(), at: 0)
    case .delete:
      guard
        let id = change.oldRecord?["id"]?.stringValue.flatMap(UUID.init(uuidString:))
      else { return }
      remove(id: id)
    default:
      break
    }
  }
}

struct CreateTodoRequest: Encodable {
  var description: String
  var isComplete: Bool
  var ownerID: UUID

  enum CodingKeys: String, CodingKey {
    case description
    case isComplete = "is_complete"
    case ownerID = "owner_id"
  }
}

struct UpdateTodoRequest: Encodable {
  var description: String?
  var isComplete: Bool?
  var ownerID: UUID

  enum CodingKeys: String, CodingKey {
    case description
    case isComplete = "is_complete"
    case ownerID = "owner_id"
  }
}
