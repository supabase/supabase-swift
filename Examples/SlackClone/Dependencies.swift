//
//  Dependencies.swift
//  SlackClone
//
//  Created by Guilherme Souza on 04/01/24.
//

import Foundation
import Supabase
import SupabaseSwiftMacros

@MainActor
class Dependencies {
  static let shared = Dependencies()

  let channel = ChannelStore.shared
  let users = UserStore.shared
  let messages = MessageStore.shared
}

@Table("users", readOnly: true)
struct User: Codable, Identifiable, Hashable {
  @PrimaryKey var id: UUID
  var username: String
}

@Table("channels")
struct Channel: Codable, Identifiable, Hashable {
  @PrimaryKey var id: Int
  @Default var insertedAt: Date
  var slug: String
  var createdBy: UUID
}

@Table("messages")
struct Message: Codable, Identifiable, Hashable {
  @PrimaryKey var id: Int
  @Default var insertedAt: Date
  var message: String
  var userId: UUID
  var channelId: Int
}

@SelectionOf(Message.self)
struct MessageWithDetails: Codable, Identifiable, Hashable {
  var id: Int
  var insertedAt: Date
  var message: String
  @Relationship(\Message.userId) var user: User
  @Relationship(\Message.channelId) var channel: Channel
}

struct UserPresence: Codable, Hashable {
  var userId: UUID
  var onlineAt: Date
}
