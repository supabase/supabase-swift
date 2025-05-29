//
//  ChannelStore.swift
//  SlackClone
//
//  Created by Guilherme Souza on 18/01/24.
//

import AsyncAlgorithms
import Foundation
import OSLog
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

      await supabase.realtimeV2.setAuth()

      let realtimeChannel = supabase.channel("channel:*") {
        $0.isPrivate = true
      }

      let insertions = realtimeChannel.broadcastStream(event: "INSERT")
      let updates = realtimeChannel.broadcastStream(event: "UPDATE")
      let deletions = realtimeChannel.broadcastStream(event: "DELETE")

      await realtimeChannel.subscribe()

      Task {
        for await event in merge(insertions, updates, deletions) {
          handleBroadcastEvent(event)
        }
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
      Logger.main.error("Failed to add channel: \(error.localizedDescription)")
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

  private func handleBroadcastEvent(_ event: BroadcastEvent) {
    do {
      let change = try event.broadcastChange()
      switch change.operation {
      case .insert(let channel):
        channels.append(try channel.decode(decoder: decoder))

      case .update(let new, _):
        let channel = try new.decode(decoder: decoder) as Channel
        if let index = channels.firstIndex(where: { $0.id == channel.id }) {
          channels[index] = channel
        } else {
          Logger.main.warning("Channel with ID \(channel.id) not found for update")
        }

      case .delete(let old):
        guard let id = old["id"]?.intValue else {
          Logger.main.error("Missing channel ID in delete operation")
          return
        }
        channels.removeAll { $0.id == id }
        messages.removeMessages(for: id)
      }
    } catch {
      Logger.main.error("Failed to handle broadcast event: \(error.localizedDescription)")
      toast = .init(status: .error, title: "Error", description: error.localizedDescription)
    }
  }

  private func fetchChannels() async -> [Channel] {
    do {
      return try await supabase.from("channels").select().execute().value
    } catch {
      Logger.main.error("Failed to fetch channels: \(error.localizedDescription)")
      toast = .init(status: .error, title: "Error", description: error.localizedDescription)
      return []
    }
  }
}
