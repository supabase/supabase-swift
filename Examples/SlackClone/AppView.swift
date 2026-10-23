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
      for await (event, session) in supabase.auth.authStateChanges {
        Logger.main.debug("AuthStateChange: \(event.rawValue)")
        guard [.signedIn, .signedOut, .initialSession, .tokenRefreshed].contains(event) else {
          return
        }
        self.session = session

        if session == nil {
          for subscription in supabase.channels {
            await subscription.unsubscribe()
          }
        }
      }
    }

    Task {
      for await status in supabase.realtime.statusChange {
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
