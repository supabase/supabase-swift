//
//  ChannelStore.swift
//  SlackClone
//
//  Created by Guilherme Souza on 18/01/24.
//

import Foundation
import Supabase

@MainActor
@Observable
final class ChannelStore {
  static let shared = ChannelStore()

  private(set) var channels: [Channel] = []
  var toast: ToastState?

  var messages: MessageStore { Dependencies.shared.messages }

  private init() {
    Task {
      channels = await fetchChannels()

      let channel = await supabase.channel("public:channels")

      let insertions = await channel.postgresChanges(
        of: Channel.self, event: .insert, table: "channels", decoder: decoder)
      let deletions = await channel.postgresChanges(
        of: Channel.self, event: .delete, table: "channels", decoder: decoder)

      try await channel.subscribe()

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

  func addChannel(_ name: String) async {
    do {
      let userId = try await supabase.auth.session().user.id
      let channel = AddChannel(slug: name, createdBy: userId)
      try await supabase
        .from("channels")
        .insert(channel)
        .execute()
    } catch {
      dump(error)
      toast = .init(status: .error, title: "Error", description: error.localizedDescription)
    }
  }

  func fetchChannel(id: Channel.ID) async throws -> Channel {
    if let channel = channels.first(where: { $0.id == id }) {
      return channel
    }

    let channel: Channel =
      try await supabase
      .from("channels")
      .select()
      .eq("id", value: id)
      .execute()
      .value
    channels.append(channel)
    return channel
  }

  private func handleInsertedChannel(_ change: TypedPostgresChange<Channel>) {
    do {
      let channel = try change.row()
      channels.append(channel)
    } catch {
      dump(error)
      toast = .init(status: .error, title: "Error", description: error.localizedDescription)
    }
  }

  private func handleDeletedChannel(_ change: TypedPostgresChange<Channel>) {
    guard let id = change.oldRecord?["id"]?.intValue else { return }
    channels.removeAll { $0.id == id }
    messages.removeMessages(for: id)
  }

  private func fetchChannels() async -> [Channel] {
    do {
      return try await supabase.from("channels").select().execute().value
    } catch {
      dump(error)
      toast = .init(status: .error, title: "Error", description: error.localizedDescription)
      return []
    }
  }
}
