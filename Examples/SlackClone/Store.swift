//
//  Store.swift
//  SlackClone
//
//  Created by Guilherme Souza on 04/01/24.
//

import Foundation
import Supabase

@MainActor
@Observable
class Store {
  static let shared = Store()

  let channel: ChannelsViewModel
  let users: UserStore
  let messages: MessagesViewModel

  private init() {
    channel = ChannelsViewModel()
    users = UserStore()
    messages = MessagesViewModel()

    channel.messages = messages
    messages.channel = channel
    messages.users = users
  }
}

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
