//
//  AppView.swift
//  SlackClone
//
//  Created by Guilherme Souza on 27/12/23.
//

import Supabase
import SwiftUI

@Observable
@MainActor
final class AppViewModel {
  var session: Session?
  var selectedChannel: Channel?

  var realtimeConnectionStatus: RealtimeClient.Status?

  init() {
    Task { [weak self] in
      for await (event, session) in supabase.auth.authStateChanges {
        guard [.signedIn, .signedOut, .initialSession].contains(event) else { return }
        self?.session = session

        if session == nil {
          for subscription in supabase.realtime.subscriptions.values {
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

@MainActor
struct AppView: View {
  @Bindable var model: AppViewModel
  let log = LogStore.shared

  @State var logPresented = false

  @ViewBuilder
  var body: some View {
    if model.session != nil {
      NavigationSplitView {
        ChannelListView(channel: $model.selectedChannel)
          .toolbar {
            ToolbarItem {
              Button("Log") {
                logPresented = true
              }
            }
          }
      } detail: {
        if let channel = model.selectedChannel {
          MessagesView(channel: channel).id(channel.id)
        }
      }
      .sheet(isPresented: $logPresented) {
        List {
          ForEach(0 ..< log.messages.count, id: \.self) { i in
            Text(log.messages[i].description)
          }
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
