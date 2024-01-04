//
//  ChannelListView.swift
//  SlackClone
//
//  Created by Guilherme Souza on 27/12/23.
//

import SwiftUI

@MainActor
struct ChannelListView: View {
  @Environment(Store.self) var store

  var body: some View {
    NavigationStack {
      List {
        ForEach(store.channels) { channel in
          NavigationLink(channel.slug, value: channel)
        }
      }
      .navigationDestination(for: Channel.self) {
        MessagesView(channel: $0)
      }
      .navigationTitle("Channels")
      .task {
        try! await store.loadInitialDataAndSetUpListeners()
      }
    }
  }
}

#Preview {
  ChannelListView()
}
