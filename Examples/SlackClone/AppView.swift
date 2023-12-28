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

  init() {
    Task { [weak self] in
      for await (event, session) in await supabase.auth.authStateChanges {
        guard [.signedIn, .signedOut, .initialSession].contains(event) else { return }
        self?.session = session
      }
    }
  }
}

struct AppView: View {
  let model: AppViewModel

  @ViewBuilder
  var body: some View {
    if model.session != nil {
      ChannelListView()
    } else {
      AuthView()
    }
  }
}

#Preview {
  AppView(model: AppViewModel())
}
