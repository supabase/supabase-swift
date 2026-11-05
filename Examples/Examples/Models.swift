import Foundation
import IdentifiedCollections
import PostgrestMacros
@_spi(Experimental) import Supabase

@Table("todos")
nonisolated struct Todo: Identifiable, Hashable {
  @PrimaryKey let id: UUID
  var description: String
  var isComplete: Bool
  let createdAt: Date
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
