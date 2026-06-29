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
struct User: Codable, Identifiable, Hashable, ReadOnlyTableRepresentable {
  @PrimaryKey var id: UUID
  var username: String
}

@Table("channels")
struct Channel: Codable, Identifiable, Hashable, TableRepresentable {
  @PrimaryKey var id: Int
  @Default var insertedAt: Date
  var slug: String
  var createdBy: UUID
}

@Table("messages")
struct Message: Codable, Identifiable, Hashable, TableRepresentable {
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

// MARK: - Typed query helpers
// Defined here so macro-generated TableRepresentable/SelectionRepresentable conformances
// are always resolved in the same compilation unit, avoiding Swift batch-compilation
// visibility issues with attached-macro-generated conformances.
extension SupabaseClient {
  // MARK: Messages
  func fetchMessages(channelId: Channel.ID) async throws -> [MessageWithDetails] {
    try await from(Message.self)
      .select(MessageWithDetails.self)
      .eq(\.channelId, value: channelId)
      .order(\.insertedAt, ascending: true)
      .execute()
      .value
  }

  func sendMessage(_ text: String, userId: UUID, channelId: Channel.ID) async throws {
    try await from(Message.self)
      .insert(Message.Insert(message: text, userId: userId, channelId: channelId))
      .execute()
  }

  // MARK: Users
  func fetchUser(id: User.ID) async throws -> User {
    try await from(User.self)
      .select()
      .eq(\.id, value: id)
      .single()
      .execute()
      .value
  }

  // MARK: Channels
  func fetchChannels() async throws -> [Channel] {
    try await from(Channel.self)
      .select()
      .execute()
      .value
  }

  func fetchChannel(id: Channel.ID) async throws -> Channel {
    try await from(Channel.self)
      .select()
      .eq(\.id, value: id)
      .single()
      .execute()
      .value
  }

  func addChannel(slug: String, createdBy: UUID) async throws {
    try await from(Channel.self)
      .insert(Channel.Insert(slug: slug, createdBy: createdBy))
      .execute()
  }
}
