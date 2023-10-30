//
//  RootView.swift
//  Examples
//
//  Created by Guilherme Souza on 22/12/22.
//

import GoTrue
import SwiftUI

struct RootView: View {
  @EnvironmentObject var auth: AuthController

  var body: some View {
    Group {
      if auth.session == nil {
        AuthView()
      } else {
        HomeView()
      }
    }
    .task {
      await auth.observeAuth()
    }
    .onOpenURL { url in
      Task {
        try? await supabase.auth.session(from: url)
      }
    }
  }
}

struct ContentView_Previews: PreviewProvider {
  static var previews: some View {
    RootView()
  }
}
