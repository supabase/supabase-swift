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
  @State private var isInfoScreenPresented = false

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
      .toolbar {
        ToolbarItem {
          Button {
            isInfoScreenPresented = true
          } label: {
            Image(systemName: "info.circle")
          }
        }
      }
      .onAppear {
        Task {
          try! await store.loadInitialDataAndSetUpListeners()
        }
      }
    }
    .sheet(isPresented: $isInfoScreenPresented) {
      List {
        Section {
          LabeledContent("Socket", value: store.socketConnectionStatus ?? "Unknown")
        }

        Section {
          LabeledContent("Messages listener", value: store.messagesListenerStatus ?? "Unknown")
          LabeledContent("Channels listener", value: store.channelsListenerStatus ?? "Unknown")
          LabeledContent("Users listener", value: store.usersListenerStatus ?? "Unknown")
        }
      }
    }
  }
}

#Preview {
  ChannelListView()
}
