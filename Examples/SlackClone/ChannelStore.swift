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

  private init() {
    Task {
      channels = await fetchChannels()
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
      channels = await fetchChannels()
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
