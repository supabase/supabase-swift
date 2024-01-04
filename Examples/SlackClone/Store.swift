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
final class Store {
  private var messagesListener: RealtimeChannelV2?
  private var channelsListener: RealtimeChannelV2?
  private var usersListener: RealtimeChannelV2?

  var channels: [Channel] = []
  var messages: [Channel.ID: [Message]] = [:]
  var users: [User.ID: User] = [:]

  func loadInitialDataAndSetUpListeners() async throws {
    channels = try await fetchChannels()

    Task {
      let channel = supabase.realtimeV2.channel("public:messages")
      messagesListener = channel

      let insertions = await channel.postgresChange(InsertAction.self, table: "messages")
      let updates = await channel.postgresChange(UpdateAction.self, table: "messages")
      let deletions = await channel.postgresChange(DeleteAction.self, table: "messages")

      await channel.subscribe(blockUntilSubscribed: true)

      Task {
        for await insertion in insertions {
          await handleInsertedOrUpdatedMessage(insertion)
        }
      }

      Task {
        for await update in updates {
          await handleInsertedOrUpdatedMessage(update)
        }
      }

      Task {
        for await delete in deletions {
          handleDeletedMessage(delete)
        }
      }
    }

    Task {
      let channel = supabase.realtimeV2.channel("public:users")
      usersListener = channel

      let changes = await channel.postgresChange(AnyAction.self, table: "users")

      await channel.subscribe(blockUntilSubscribed: true)

      for await change in changes {
        handleChangedUser(change)
      }
    }

    Task {
      let channel = supabase.realtimeV2.channel("public:channels")
      channelsListener = channel

      let insertions = await channel.postgresChange(InsertAction.self, table: "channels")
      let deletions = await channel.postgresChange(DeleteAction.self, table: "channels")

      await channel.subscribe(blockUntilSubscribed: true)

      Task {
        for await insertion in insertions {
          handleInsertedChannel(insertion)
        }
      }

      Task {
        for await delete in deletions {
          handleDeletedChannel(delete)
        }
      }
    }
  }

  func loadInitialMessages(_: Channel.ID) async {}

  private func handleInsertedOrUpdatedMessage(_ action: HasRecord) async {
    do {
      let decodedMessage = try action.decodeRecord() as MessagePayload
      let message = try await Message(
        id: decodedMessage.id,
        insertedAt: decodedMessage.insertedAt,
        message: decodedMessage.message,
        user: fetchUser(id: decodedMessage.authorId),
        channel: fetchChannel(id: decodedMessage.channelId)
      )

      if let index = messages[decodedMessage.channelId, default: []]
        .firstIndex(where: { $0.id == message.id })
      {
        messages[decodedMessage.channelId]?[index] = message
      } else {
        messages[decodedMessage.channelId]?.append(message)
      }
    } catch {
      dump(error)
    }
  }

  private func handleDeletedMessage(_: DeleteAction) {}

  private func handleChangedUser(_: AnyAction) {}

  private func handleInsertedChannel(_: InsertAction) {}
  private func handleDeletedChannel(_: DeleteAction) {}

  /// Fetch all messages and their authors.
  private func fetchMessages(_ channelId: Channel.ID) async throws -> [Message] {
    try await supabase.database
      .from("messages")
      .select("*,author:user_id(*),channel:channel_id(*)")
      .eq("channel_id", value: channelId)
      .order("inserted_at", ascending: true)
      .execute()
      .value
  }

  /// Fetch a single user.
  private func fetchUser(id: UUID) async throws -> User {
    if let user = users[id] {
      return user
    }

    let user = try await supabase.database.from("users").select().eq("id", value: id).single()
      .execute().value as User
    users[user.id] = user
    return user
  }

  /// Fetch a single channel.
  private func fetchChannel(id: Channel.ID) async throws -> Channel {
    if let channel = channels.first(where: { $0.id == id }) {
      return channel
    }

    let channel = try await supabase.database.from("channels").select().eq("id", value: id)
      .execute().value as Channel
    channels.append(channel)
    return channel
  }

  private func fetchChannels() async throws -> [Channel] {
    try await supabase.database.from("channels").select().execute().value
  }
}

private struct MessagePayload: Decodable {
  let id: Int
  let message: String
  let insertedAt: Date
  let authorId: UUID
  let channelId: Int
}
