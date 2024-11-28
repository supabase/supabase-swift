//
//  AppView.swift
//  SlackClone
//
//  Created by Guilherme Souza on 27/12/23.
//

import OSLog
import Supabase
import SwiftUI

@Observable
@MainActor
final class AppViewModel {
  var session: Session?
  var selectedChannel: Channel?

  var realtimeConnectionStatus: RealtimeClientStatus?

  let channelStore = ChannelStore()
  let messageStore = MessageStore()
  let userStore = UserStore()

  init() {
    channelStore.messages = messageStore
    messageStore.channel = channelStore
    messageStore.users = userStore

    Task {
      for await (event, session) in supabase.auth.authStateChanges {
        Logger.main.debug("AuthStateChange: \(event.rawValue)")
        guard [.signedIn, .signedOut, .initialSession, .tokenRefreshed].contains(event) else {
          return
        }
        self.session = session

        if session == nil {
          for subscription in await supabase.channels {
            await subscription.unsubscribe()
          }
        }
      }
    }

    Task {
      for await status in await supabase.realtimeV2.statusChange {
        realtimeConnectionStatus = status
      }
    }
  }
}

struct AppView: View {
  @Bindable var model: AppViewModel
  @State var logPresented = false

  @ViewBuilder
  var body: some View {
    if model.session != nil {
      NavigationSplitView {
        ChannelListView(channel: $model.selectedChannel)
      } detail: {
        if let channel = model.selectedChannel {
          MessagesView(channel: channel).id(channel.id)
        }
      }
      .environment(model.channelStore)
      .environment(model.messageStore)
      .environment(model.userStore)
    } else {
      AuthView()
    }
  }
}

#Preview {
  AppView(model: AppViewModel())
}
