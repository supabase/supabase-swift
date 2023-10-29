//
//  RootView.swift
//  Examples
//
//  Created by Guilherme Souza on 22/12/22.
//

import GoTrue
import SwiftUI

extension Session {
  static var current: Session?
}

@MainActor
final class RootViewModel: ObservableObject {
  let authViewModel = AuthViewModel()

  @Published private(set) var session: Session?

  init() {
    Task {
      for await event in await supabase.auth.onAuthStateChange() {
        logger.info("event changed: \(event.rawValue)")

        guard event == .signedIn || event == .signedOut else {
          return
        }

        let session = try? await supabase.auth.session
        self.session = session
        Session.current = session
      }
    }
  }
}

struct RootView: View {
  @ObservedObject var model: RootViewModel

  var body: some View {
    Group {
      if model.session == nil {
        AuthView(model: model.authViewModel)
      } else {
        HomeView()
      }
    }
    .onOpenURL { url in
      Task {
        try? await supabase.auth.session(from: url)
      }
    }
  }
}
