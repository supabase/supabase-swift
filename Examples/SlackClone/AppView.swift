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

  var realtimeConnectionStatus: RealtimeClientV2.Status?

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

    Task {
      for await status in await supabase.realtimeV2.statusChange {
        realtimeConnectionStatus = status
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
      .overlay(alignment: .bottom) {
        LabeledContent(
          "Connection Status",
          value: model.realtimeConnectionStatus?.description ?? "Unknown"
        )
        .padding()
        .background(.regularMaterial)
        .clipShape(Capsule())
        .padding()
      }
    } else {
      AuthView()
    }
  }
}

#Preview {
  AppView(model: AppViewModel())
}
