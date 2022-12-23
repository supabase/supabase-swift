//
//  File.swift
//  Examples
//
//  Created by Guilherme Souza on 23/12/22.
//

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

  enum CodingKeys: String, CodingKey {
    case description
    case isComplete = "is_complete"
  }
}

struct UpdateTodoRequest: Encodable {
  var description: String?
  var isComplete: Bool?

  enum CodingKeys: String, CodingKey {
    case description
    case isComplete = "is_complete"
  }
}
