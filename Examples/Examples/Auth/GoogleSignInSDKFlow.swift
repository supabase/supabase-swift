//
//  GoogleSignInSDKFlow.swift
//  Examples
//
//  Created by Guilherme Souza on 05/03/24.
//

import SwiftUI
@preconcurrency import GoogleSignIn
import GoogleSignInSwift
import Supabase

@MainActor
struct GoogleSignInSDKFlow: View {
  var body: some View {
    GoogleSignInButton(action: handleSignIn)
  }

  func handleSignIn() {
    Task {
      do {
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)

        guard let idToken = result.user.idToken?.tokenString else {
          debug("No 'idToken' returned by GIDSignIn call.")
          return
        }

        try await supabase.auth.signInWithIdToken(
          credentials: OpenIDConnectCredentials(
            provider: .google,
            idToken: idToken
          )
        )
      } catch {
        debug("GoogleSignIn failed: \(error)")
      }
    }
  }

  var rootViewController: UIViewController {
    UIApplication.shared.firstKeyWindow?.rootViewController ?? UIViewController()
  }
}

#Preview {
  GoogleSignInSDKFlow()
}
