//
//  RootView.swift
//  Examples
//
//  Created by Guilherme Souza on 22/12/22.
//

import SwiftUI
import GoTrue

struct RootView: View {
  @State var authEvent: AuthChangeEvent?

  var body: some View {
    Group {
      if authEvent == .signedOut {
        AuthView()
      } else {
        HomeView()
      }
    }
    .task {
      for await event in supabase.auth.authEventChange {
        withAnimation {
          authEvent = event
        }
      }
    }
  }
}

struct ContentView_Previews: PreviewProvider {
  static var previews: some View {
    RootView()
  }
}
