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

  var messagesListenerStatus: String?
  var channelsListenerStatus: String?
  var usersListenerStatus: String?
  var socketConnectionStatus: String?

  var channels: [Channel] = []
  var messages: [Channel.ID: [Message]] = [:]
  var users: [User.ID: User] = [:]

  func loadInitialDataAndSetUpListeners() async throws {
    if messagesListener != nil, channelsListener != nil, usersListener != nil {
      return
    }

    channels = try await fetchChannels()

    Task {
      for await status in await supabase.realtimeV2.status.values {
        self.socketConnectionStatus = String(describing: status)
      }
    }

    Task {
      let channel = await supabase.realtimeV2.channel("public:messages")
      messagesListener = channel

      Task {
        for await status in await channel.status.values {
          self.messagesListenerStatus = String(describing: status)
        }
      }

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
      let channel = await supabase.realtimeV2.channel("public:users")
      usersListener = channel

      Task {
        for await status in await channel.status.values {
          self.usersListenerStatus = String(describing: status)
        }
      }

      let changes = await channel.postgresChange(AnyAction.self, table: "users")

      await channel.subscribe(blockUntilSubscribed: true)

      for await change in changes {
        handleChangedUser(change)
      }
    }

    Task {
      let channel = await supabase.realtimeV2.channel("public:channels")
      channelsListener = channel

      Task {
        for await status in await channel.status.values {
          self.channelsListenerStatus = String(describing: status)
        }
      }

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

  func loadInitialMessages(_ channelId: Channel.ID) async {
    do {
      messages[channelId] = try await fetchMessages(channelId)
    } catch {
      dump(error)
    }
  }

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

  private func handleDeletedMessage(_ action: DeleteAction) {
    guard let id = action.oldRecord["id"]?.intValue else {
      return
    }

    let allMessages = messages.flatMap(\.value)
    guard let message = allMessages.first(where: { $0.id == id }) else { return }

    messages[message.channel.id]?.removeAll(where: { $0.id == message.id })
  }

  private func handleChangedUser(_ action: AnyAction) {
    do {
      switch action {
      case let .insert(action):
        let user = try action.decodeRecord() as User
        users[user.id] = user
      case let .update(action):
        let user = try action.decodeRecord() as User
        users[user.id] = user
      case let .delete(action):
        guard let id = action.oldRecord["id"]?.stringValue else { return }
        users[UUID(uuidString: id)!] = nil
      default:
        break
      }
    } catch {
      dump(error)
    }
  }

  private func handleInsertedChannel(_ action: InsertAction) {
    do {
      let channel = try action.decodeRecord() as Channel
      channels.append(channel)
    } catch {
      dump(error)
    }
  }

  private func handleDeletedChannel(_ action: DeleteAction) {
    guard let id = action.oldRecord["id"]?.intValue else { return }
    channels.removeAll { $0.id == id }
    messages[id] = nil
  }

  /// Fetch all messages and their authors.
  private func fetchMessages(_ channelId: Channel.ID) async throws -> [Message] {
    try await supabase.database
      .from("messages")
      .select("*,user:user_id(*),channel:channel_id(*)")
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
