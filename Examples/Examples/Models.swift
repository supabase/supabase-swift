import Foundation

struct Todo: Identifiable, Hashable, Decodable {
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
