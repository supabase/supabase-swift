//
//  MessagesViewModel.swift
//  SlackClone
//
//  Created by Guilherme Souza on 18/01/24.
//

import Foundation
import Supabase

@MainActor
protocol MessagesStore: AnyObject {
  func removeMessages(for channel: Channel.ID)
}

@MainActor
@Observable
final class MessagesViewModel: MessagesStore {
  private(set) var messages: [Channel.ID: [Message]] = [:]

  weak var users: UserStore!
  weak var channel: ChannelsStore!

  init() {
    Task {
      let channel = await supabase.realtimeV2.channel("public:messages")

      let insertions = await channel.postgresChange(InsertAction.self, table: "messages")
      let updates = await channel.postgresChange(UpdateAction.self, table: "messages")
      let deletions = await channel.postgresChange(DeleteAction.self, table: "messages")

      await channel.subscribe()

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
  }

  func loadInitialMessages(_ channelId: Channel.ID) async {
    do {
      messages[channelId] = try await fetchMessages(channelId)
    } catch {
      dump(error)
    }
  }

  func removeMessages(for channel: Channel.ID) {
    messages[channel] = []
  }

  private func handleInsertedOrUpdatedMessage(_ action: HasRecord) async {
    do {
      let decodedMessage = try action.decodeRecord(decoder: decoder) as MessagePayload
      let message = try await Message(
        id: decodedMessage.id,
        insertedAt: decodedMessage.insertedAt,
        message: decodedMessage.message,
        user: users.fetchUser(id: decodedMessage.userId),
        channel: channel.fetchChannel(id: decodedMessage.channelId)
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
}

private struct MessagePayload: Decodable {
  let id: Int
  let message: String
  let insertedAt: Date
  let userId: UUID
  let channelId: Int
}
