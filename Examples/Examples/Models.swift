import Foundation

struct Todo: Identifiable, Hashable, Decodable {
  let id: Int
  let task: String
  var isComplete: Bool
  let insertedAt: Date
}

struct CreateTodoRequest: Encodable {
  var task: String
  var isComplete: Bool
  var userId: UUID
}

struct UpdateTodoRequest: Encodable {
  var task: String?
  var isComplete: Bool?
  var userId: UUID
}
