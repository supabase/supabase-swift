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
      let contextProvider = DefaultPresentationContextProvider()

      try await supabase.auth.signInWithOAuth(provider: .google) {
        $0.presentationContextProvider = contextProvider
      }
    } catch {
      print("failed to sign in with Google: \(error)")
    }
  }
}

#Preview {
  GoogleSignInWithWebFlow()
}

final class DefaultPresentationContextProvider: NSObject,
  ASWebAuthenticationPresentationContextProviding, Sendable
{
  func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
    if Thread.isMainThread {
      return MainActor.assumeIsolated {
        ASPresentationAnchor()
      }
    } else {
      return DispatchQueue.main.sync {
        MainActor.assumeIsolated {
          ASPresentationAnchor()
        }
      }
    }
  }
}
