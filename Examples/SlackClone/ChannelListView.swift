//
//  ChannelListView.swift
//  SlackClone
//
//  Created by Guilherme Souza on 27/12/23.
//

import SwiftUI

@Observable
@MainActor
final class ChannelListModel {
  var channels: [Channel] = []

  func loadChannels() {
    Task {
      do {
        channels = try await supabase.database.from("channels").select().execute().value
      } catch {
        dump(error)
      }
    }
  }
}

@MainActor
struct ChannelListView: View {
  let model = ChannelListModel()

  var body: some View {
    NavigationStack {
      List {
        ForEach(model.channels) { channel in
          NavigationLink(channel.slug, value: channel)
        }
      }
      .navigationDestination(for: Channel.self) {
        MessagesView(model: MessagesViewModel(channel: $0))
      }
      .navigationTitle("Channels")
      .onAppear {
        model.loadChannels()
      }
    }
  }
}

#Preview {
  ChannelListView()
}
