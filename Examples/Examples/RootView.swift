//
//  RootView.swift
//  Examples
//
//  Created by Guilherme Souza on 22/12/22.
//

import Supabase
import SwiftUI

struct RootView: View {
  @Environment(AuthModel.self) private var auth
  @Environment(\.supabase) private var supabase

  @State private var isPasswordRecovery = false
  @State private var redirectMessage: String?

  var body: some View {
    Group {
      switch auth.status {
      case .loading:
        ProgressView()
      case .signedOut:
        NavigationStack {
          AuthExamplesView()
        }
      case .signedIn:
        HomeView()
      }
    }
    .onOpenURL { url in
      Task { await handle(url) }
    }
    .task {
      for await change in supabase.auth.events() where change.event == .passwordRecovery {
        isPasswordRecovery = true
      }
    }
    .sheet(isPresented: $isPasswordRecovery) {
      UpdatePasswordView()
    }
    .alert(
      "Check your other inbox",
      isPresented: Binding(
        get: { redirectMessage != nil },
        set: { if !$0 { redirectMessage = nil } }
      )
    ) {
      Button("OK") {}
    } message: {
      Text(redirectMessage ?? "")
    }
  }

  private func handle(_ url: URL) async {
    do {
      switch try await supabase.handleRedirect(url) {
      case .signedIn(_, verification: .recovery)?:
        isPasswordRecovery = true
      case .emailChangePending(let message)?:
        redirectMessage = message
      case .signedIn?, nil:
        break
      }
    } catch {
      debug("Failed to handle a redirect: \(error)")
    }
  }
}

#Preview {
  RootView()
    .environment(AuthModel(client: supabaseClient.auth))
    .environment(\.supabase, supabaseClient)
}
