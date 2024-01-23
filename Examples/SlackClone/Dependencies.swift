//
//  Dependencies.swift
//  SlackClone
//
//  Created by Guilherme Souza on 04/01/24.
//

import Foundation
import Supabase

class Dependencies {
  static let shared = Dependencies()

  let channel = ChannelStore.shared
  let users = UserStore.shared
  let messages = MessageStore.shared
}

struct User: Codable, Identifiable, Hashable {
  var id: UUID
  var username: String
  var status: Status = .offline

  enum Status: String, Codable {
    case online = "ONLINE"
    case offline = "OFFLINE"
  }
}

struct AddChannel: Encodable {
  var slug: String
  var createdBy: UUID
}

struct Channel: Identifiable, Codable, Hashable {
  var id: Int
  var slug: String
  var insertedAt: Date
}

struct Message: Identifiable, Decodable, Hashable {
  var id: Int
  var insertedAt: Date
  var message: String
  var user: User
  var channel: Channel
}

struct NewMessage: Codable {
  var message: String
  var userId: UUID
  let channelId: Int
}

struct UserPresence: Codable {
  var userId: UUID
  var onlineAt: Date
}
