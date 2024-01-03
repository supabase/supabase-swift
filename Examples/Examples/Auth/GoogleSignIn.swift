//
//  GoogleSignIn.swift
//  Examples
//
//  Created by Guilherme Souza on 22/12/23.
//

import SwiftUI
import AuthenticationServices

struct GoogleSignIn: View {
  @Environment(\.webAuthenticationSession) var webAuthenticationSession

  var body: some View {
    Button("Sign in with Google") {
      Task {
        await signInWithGoogleButtonTapped()
      }
    }
  }

  private func signInWithGoogleButtonTapped() async {
    do {
      let url = try await supabase.auth.getOAuthSignInURL(
        provider: .google,
        redirectTo: Constants.redirectToURL
      )
      let urlWithToken = try await webAuthenticationSession.authenticate(
        using: url,
        callbackURLScheme: Constants.redirectToURL.scheme!
      )
      try await supabase.auth.session(from: urlWithToken)
    } catch {
      print("failed to sign in with Google: \(error)")
    }
  }
}

#Preview {
  GoogleSignIn()
}
