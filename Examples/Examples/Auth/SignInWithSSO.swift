//
//  SignInWithSSO.swift
//  Examples
//
//  Demonstrates SAML single sign-on with the default presenter
//

import Supabase
import SwiftUI

struct SignInWithSSO: View {
  @Environment(\.supabase) private var supabase

  @State private var domain = ""
  @State private var actionState = ActionState<Void, Error>.idle

  var body: some View {
    List {
      Section {
        Text(
          "Sign in with the SAML identity provider registered for your email domain. The SDK shows the provider page and signs you in."
        )
        .font(.caption)
        .foregroundColor(.secondary)
      }

      Section("Email domain") {
        TextField("example.com", text: $domain)
          .autocorrectionDisabled()
          #if !os(macOS)
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
          #endif

        Button("Sign in with SSO") {
          Task { await signIn() }
        }
        .disabled(domain.isEmpty)
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
            try await supabase.auth.signInWithSSO(
              .domain("example.com"),
              options: SSOOptions(redirectTo: redirectURL)
            )
            """
        )
      }
    }
    .navigationTitle("Single Sign-On")
    .gitHubSourceLink()
  }

  private func signIn() async {
    actionState = .inFlight
    do {
      try await supabase.auth.signInWithSSO(
        .domain(domain),
        options: SSOOptions(redirectTo: Constants.redirectToURL)
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
    SignInWithSSO()
  }
  .environment(\.supabase, supabaseClient)
}
