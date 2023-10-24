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
  @State var handle: AuthStateListenerHandle?

  @EnvironmentObject var auth: AuthController

  var body: some View {
    Group {
      if authEvent == .signedOut {
        AuthView()
      } else {
        HomeView()
      }
    }
    .onAppear {
      handle = supabase.auth.onAuthStateChange { event, session in
        withAnimation {
          authEvent = event
        }
        auth.session = session
      }
    }
    .onDisappear {
      handle?.unsubscribe()
    }
  }
}

struct ContentView_Previews: PreviewProvider {
  static var previews: some View {
    RootView()
  }
}
