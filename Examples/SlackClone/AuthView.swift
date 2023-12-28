//
//  AuthView.swift
//  SlackClone
//
//  Created by Guilherme Souza on 27/12/23.
//

import SwiftUI

@Observable
@MainActor
final class AuthViewModel {
  var email = ""
  var toast: ToastState?

  func signInButtonTapped() {
    Task {
      do {
        try await supabase.auth.signInWithOTP(
          email: email,
          redirectTo: URL(string: "slackclone://sign-in")
        )
        toast = ToastState(status: .success, title: "Check your inbox.")
      } catch {
        toast = ToastState(status: .error, title: "Error", description: error.localizedDescription)
      }
    }
  }

  func handle(_ url: URL) {
    Task {
      do {
        try await supabase.auth.session(from: url)
      } catch {
        toast = ToastState(status: .error, title: "Error", description: error.localizedDescription)
      }
    }
  }
}

@MainActor
struct AuthView: View {
  @Bindable var model = AuthViewModel()

  var body: some View {
    VStack {
      VStack {
        TextField("Email", text: $model.email)
        #if os(iOS)
          .textInputAutocapitalization(.never)
          .keyboardType(.emailAddress)
        #endif
          .textContentType(.emailAddress)
          .autocorrectionDisabled()
      }
      Button("Sign in with Magic Link") {
        model.signInButtonTapped()
      }
    }
    .padding()
    .toast(state: $model.toast)
    .onOpenURL { model.handle($0) }
  }
}

#Preview {
  AuthView()
}
