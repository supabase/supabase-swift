//
//  ChannelStore.swift
//  SlackClone
//
//  Created by Guilherme Souza on 18/01/24.
//

import Foundation
import Supabase
import SupabaseSwiftMacros

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

      let channel = supabase.channel("public:channels")

      let insertions = channel.postgresChange(InsertAction.self, table: "channels")
      let deletions = channel.postgresChange(DeleteAction.self, table: "channels")

      try await channel.subscribeWithError()

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
      let userId = try await supabase.auth.session.user.id
      try await supabase.addChannel(slug: name, createdBy: userId)
    } catch {
      dump(error)
      toast = .init(status: .error, title: "Error", description: error.localizedDescription)
    }
  }

  func fetchChannel(id: Channel.ID) async throws -> Channel {
    if let channel = channels.first(where: { $0.id == id }) {
      return channel
    }

    let channel = try await supabase.fetchChannel(id: id)
    channels.append(channel)
    return channel
  }

  private func handleInsertedChannel(_ action: InsertAction) {
    do {
      let channel = try action.decodeRecord(decoder: decoder) as Channel
      channels.append(channel)
    } catch {
      dump(error)
      toast = .init(status: .error, title: "Error", description: error.localizedDescription)
    }
  }

  private func handleDeletedChannel(_ action: DeleteAction) {
    guard let id = action.oldRecord["id"]?.intValue else { return }
    channels.removeAll { $0.id == id }
    messages.removeMessages(for: id)
  }

  private func fetchChannels() async -> [Channel] {
    do {
      return try await supabase.fetchChannels()
    } catch {
      dump(error)
      toast = .init(status: .error, title: "Error", description: error.localizedDescription)
      return []
    }
  }
}
