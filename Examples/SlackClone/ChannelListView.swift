//
//  ChannelListView.swift
//  SlackClone
//
//  Created by Guilherme Souza on 27/12/23.
//

import SwiftUI

struct ChannelListView: View {
  @Bindable var store = Dependencies.shared.channel
  @Binding var channel: Channel?

  @State private var addChannelPresented = false
  @State private var newChannelName = ""

  var body: some View {
    List(store.channels, selection: $channel) { channel in
      NavigationLink(channel.slug, value: channel)
    }
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button("Add Channel") {
          addChannelPresented = true
        }
        .popover(isPresented: $addChannelPresented) {
          addChannelView
        }
      }
      ToolbarItem {
        Button("Log out") {
          Task {
            try? await supabase.auth.signOut()
          }
        }
      }
    }
    .toast(state: $store.toast)
  }

  private var addChannelView: some View {
    Form {
      Section {
        TextField("New channel name", text: $newChannelName)
      }

      Section {
        Button("Add") {
          Task {
            await store.addChannel(newChannelName)
            addChannelPresented = false
          }
        }
      }
    }
    #if os(macOS)
    .padding()
    #endif
  }
}
