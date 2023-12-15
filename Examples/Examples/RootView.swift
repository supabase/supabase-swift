//
//  RootView.swift
//  Examples
//
//  Created by Guilherme Souza on 22/12/22.
//

import Auth
import SwiftUI

struct RootView: View {
  @Environment(AuthController.self) var auth

  var body: some View {
    NavigationStack {
      if auth.session == nil {
        AuthView()
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

struct ContentView_Previews: PreviewProvider {
  static var previews: some View {
    RootView()
  }
}
