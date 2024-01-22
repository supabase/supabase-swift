//
//  ChannelListView.swift
//  SlackClone
//
//  Created by Guilherme Souza on 27/12/23.
//

import SwiftUI

@MainActor
struct ChannelListView: View {
  let store = Store.shared.channel
  @Binding var channel: Channel?

  var body: some View {
    List(store.channels, selection: $channel) { channel in
      NavigationLink(channel.slug, value: channel)
    }
    .toolbar {
      ToolbarItem {
        Button("Log out") {
          Task {
            try? await supabase.auth.signOut()
          }
        }
      }
    }
  }
}
