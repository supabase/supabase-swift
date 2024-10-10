//
//  AuthWithMagicLink.swift
//  Examples
//
//  Created by Guilherme Souza on 15/12/23.
//

import SwiftUI

struct AuthWithMagicLink: View {
  @State var email = ""
  @State var actionState: ActionState<Void, Error> = .idle

  var body: some View {
    Form {
      Section {
        TextField("Email", text: $email)
          .textContentType(.emailAddress)
          .autocorrectionDisabled()
        #if !os(macOS)
          .keyboardType(.emailAddress)
          .textInputAutocapitalization(.never)
        #endif
      }

      Section {
        Button("Sign in with magic link") {
          Task {
            await signInWithMagicLinkTapped()
          }
        }
      }

      switch actionState {
      case .idle, .result(.success):
        EmptyView()
      case .inFlight:
        ProgressView()
      case let .result(.failure(error)):
        ErrorText(error)
      }
    }
    .onOpenURL { url in
      Task { await onOpenURL(url) }
    }
  }

  private func signInWithMagicLinkTapped() async {
    actionState = .inFlight

    actionState = await .result(
      Result {
        try await supabase.auth.signInWithOTP(
          email: email,
          redirectTo: Constants.redirectToURL
        )
      }
    )
  }

  private func onOpenURL(_ url: URL) async {
    debug("received url: \(url)")

    actionState = .inFlight
    actionState = await .result(
      Result {
        try await supabase.auth.session(from: url)
      }
    )
  }
}

#Preview {
  AuthWithMagicLink()
}
