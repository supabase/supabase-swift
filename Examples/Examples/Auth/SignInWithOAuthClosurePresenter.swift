//
//  SignInWithOAuthClosurePresenter.swift
//  Examples
//
//  Shows the provider page with SwiftUI's `webAuthenticationSession` through a ClosurePresenter
//

import AuthenticationServices
import Supabase
import SwiftUI

struct SignInWithOAuthClosurePresenter: View {
  @Environment(\.supabase) private var supabase
  @Environment(\.webAuthenticationSession) private var webAuthenticationSession

  @State private var provider = knownProviders[0]
  @State private var actionState = ActionState<Void, Error>.idle

  var body: some View {
    List {
      Section {
        Text(
          "The default presenter shows the provider page with ASWebAuthenticationSession. Pass a ClosurePresenter to show it another way, here with SwiftUI's webAuthenticationSession."
        )
        .font(.caption)
        .foregroundColor(.secondary)
      }

      Section("Provider") {
        Picker("Provider", selection: $provider) {
          ForEach(knownProviders, id: \.self) { provider in
            Text(provider.rawValue).tag(provider)
          }
        }

        Button("Start Sign-in Flow") {
          Task { await signIn() }
        }
      }

      switch actionState {
      case .idle, .result(.success):
        EmptyView()
      case .inFlight:
        ProgressView()
      case .result(.failure(let error)):
        ErrorText(error)
      }

      Section("Code Example") {
        CodeExample(
          code: """
            @Environment(\\.webAuthenticationSession) private var webAuthenticationSession

            try await supabase.auth.signInWithOAuth(
              .github,
              options: OAuthOptions(redirectTo: redirectURL),
              presenter: ClosurePresenter { [webAuthenticationSession] url, callbackScheme in
                try await webAuthenticationSession.authenticate(
                  using: url,
                  callbackURLScheme: callbackScheme ?? "myapp"
                )
              }
            )
            """
        )
      }
    }
    .navigationTitle("OAuth with a ClosurePresenter")
    .gitHubSourceLink()
  }

  private func signIn() async {
    actionState = .inFlight
    do {
      try await supabase.auth.signInWithOAuth(
        provider,
        options: OAuthOptions(redirectTo: Constants.redirectToURL),
        presenter: ClosurePresenter { [webAuthenticationSession] url, callbackScheme in
          try await webAuthenticationSession.authenticate(
            using: url,
            callbackURLScheme: callbackScheme ?? Constants.redirectScheme
          )
        }
      )
      actionState = .result(.success(()))
    } catch is CancellationError {
      actionState = .idle
    } catch {
      actionState = .result(.failure(error))
    }
  }
}

#Preview {
  NavigationStack {
    SignInWithOAuthClosurePresenter()
  }
}
