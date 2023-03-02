//
//  RootView.swift
//  Examples
//
//  Created by Guilherme Souza on 22/12/22.
//

import GoTrue
import SwiftUI

struct RootView: View {
  @State var authEvent: AuthChangeEvent?
  @EnvironmentObject var auth: AuthController

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

        auth.session = try? await supabase.auth.session
      }
    }
  }
}

struct ContentView_Previews: PreviewProvider {
  static var previews: some View {
    RootView()
  }
}
