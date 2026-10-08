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

      let channel = supabase.channel("public:channels")
      let changes = channel.postgresChanges(of: Channel.self, table: "channels", decoder: decoder)

      do {
        try await channel.subscribe()
      } catch {
        dump(error)
        return
      }

      for await change in changes {
        handleChange(change)
      }
    }
  }

  func addChannel(_ name: String) async {
    do {
      let userId = try await supabase.auth.session.user.id
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

  private func handleChange(_ change: TypedPostgresChange<Channel>) {
    switch change.kind {
    case .insert:
      do {
        channels.append(try change.row())
      } catch {
        dump(error)
        toast = .init(status: .error, title: "Error", description: error.localizedDescription)
      }
    case .update:
      break
    case .delete:
      guard let id = change.oldRecord?["id"]?.intValue else { return }
      channels.removeAll { $0.id == id }
      messages.removeMessages(for: id)
    }
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
