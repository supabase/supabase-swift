//
//  GoogleSignInWithWebFlow.swift
//  Examples
//
//  Created by Guilherme Souza on 22/12/23.
//

import AuthenticationServices
import SwiftUI

struct GoogleSignInWithWebFlow: View {
  @Environment(\.webAuthenticationSession) var webAuthenticationSession

  var body: some View {
    Button("Sign in with Google") {
      Task {
        await signInWithGoogleButtonTapped()
      }
    }
  }

  @MainActor
  private func signInWithGoogleButtonTapped() async {
    do {
      try await supabase.auth.signInWithOAuth(provider: .google) { url in
        try await webAuthenticationSession.authenticate(
          using: url,
          callbackURLScheme: url.scheme!
        )
      }
    } catch {
      print("failed to sign in with Google: \(error)")
    }
  }
}

#Preview {
  GoogleSignInWithWebFlow()
}
