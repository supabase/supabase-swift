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

  init() {
    Task {
      for await change in supabase.auth.events() {
        Logger.main.debug("AuthStateChange: \(change.event.rawValue)")
        guard [.signedIn, .signedOut, .initialSession, .tokenRefreshed].contains(change.event)
        else {
          return
        }
        self.session = change.session

        if change.session == nil {
          for subscription in await supabase.channels {
            await subscription.unsubscribe()
          }
        }
      }
    }

    Task {
      for await status in await supabase.realtime.statusChanges() {
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
    } else {
      AuthView()
    }
  }
}

#Preview {
  AppView(model: AppViewModel())
}
