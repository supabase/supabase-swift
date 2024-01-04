//
//  MessagesAPI.swift
//  SlackClone
//
//  Created by Guilherme Souza on 27/12/23.
//

import Foundation
import Supabase

struct User: Codable, Identifiable {
  var id: UUID
  var username: String
}

struct Channel: Identifiable, Codable, Hashable {
  var id: Int
  var slug: String
  var insertedAt: Date
}

struct Message: Identifiable, Decodable {
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

protocol MessagesAPI {
  func fetchAllMessages(for channelId: Int) async throws -> [Message]
  func insertMessage(_ message: NewMessage) async throws
}

struct MessagesAPIImpl: MessagesAPI {
  let supabase: SupabaseClient

  func fetchAllMessages(for channelId: Int) async throws -> [Message] {
    try await supabase.database.from("messages")
      .select("*,user:users(*),channel:channels(*)")
      .eq("channel_id", value: channelId)
      .execute()
      .value
  }

  func insertMessage(_ message: NewMessage) async throws {
    try await supabase.database
      .from("messages")
      .insert(message)
      .execute()
  }
}
