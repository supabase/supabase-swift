//
//  ChannelsViewModel.swift
//  SlackClone
//
//  Created by Guilherme Souza on 18/01/24.
//

import Foundation
import Supabase

protocol ChannelsStore: AnyObject {
  func fetchChannel(id: Channel.ID) async throws -> Channel
}

@MainActor
@Observable
final class ChannelsViewModel: ChannelsStore {
  private(set) var channels: [Channel] = []

  weak var messages: MessagesStore!

  init() {
    Task {
      channels = try await fetchChannels()

      let channel = await supabase.realtimeV2.channel("public:channels")

      let insertions = await channel.postgresChange(InsertAction.self, table: "channels")
      let deletions = await channel.postgresChange(DeleteAction.self, table: "channels")

      await channel.subscribe()

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

  func fetchChannel(id: Channel.ID) async throws -> Channel {
    if let channel = channels.first(where: { $0.id == id }) {
      return channel
    }

    let channel: Channel = try await supabase.database
      .from("channels")
      .select()
      .eq("id", value: id)
      .execute()
      .value
    channels.append(channel)
    return channel
  }

  private func handleInsertedChannel(_ action: InsertAction) {
    do {
      let channel = try action.decodeRecord(decoder: decoder) as Channel
      channels.append(channel)
    } catch {
      dump(error)
    }
  }

  private func handleDeletedChannel(_ action: DeleteAction) {
    guard let id = action.oldRecord["id"]?.intValue else { return }
    channels.removeAll { $0.id == id }
    messages.removeMessages(for: id)
  }

  private func fetchChannels() async throws -> [Channel] {
    try await supabase.database.from("channels").select().execute().value
  }
}
