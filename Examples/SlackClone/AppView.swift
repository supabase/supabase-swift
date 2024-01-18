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

  init() {
    Task { [weak self] in
      for await (event, session) in await supabase.auth.authStateChanges {
        guard [.signedIn, .signedOut, .initialSession].contains(event) else { return }
        self?.session = session

        if session == nil {
          for subscription in await supabase.realtimeV2.subscriptions.values {
            await subscription.unsubscribe()
          }
        }
      }
    }
  }
}

@MainActor
struct AppView: View {
  @Bindable var model: AppViewModel

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
