//
//  AuthWithMagicLink.swift
//  Examples
//
//  Created by Guilherme Souza on 15/12/23.
//

import SwiftUI

struct AuthWithMagicLink: View {
  @State var email = ""
  @State var error: Error?

  var body: some View {
    Form {
      Section {
        TextField("Email", text: $email)
      }

      Section {
        Button("Sign in with magic link") {
          Task {
            await signInWithMagicLinkTapped()
          }
        }
      }
    }
    .onOpenURL { url in
      Task { await onOpenURL(url) }
    }
  }

  private func signInWithMagicLinkTapped() async {
    do {
      try await supabase.auth.signInWithOTP(
        email: email,
        redirectTo: URL(string: "com.supabase.Examples://")
      )
    } catch {
      self.error = error
    }
  }

  private func onOpenURL(_ url: URL) async {
    debug("onOpenURL: \(url)")

    do {
      try await supabase.auth.session(from: url)
    } catch {
      self.error = error
    }
  }
}

#Preview {
  AuthWithMagicLink()
}
