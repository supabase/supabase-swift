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

  func signInButtonTapped() async {
    do {
      try await supabase.auth.signInWithOTP(email: email)
      toast = ToastState(status: .success, title: "Check your inbox.")

      try? await Task.sleep(for: .seconds(1))

      #if os(macOS)
        NSWorkspace.shared.open(URL(string: "http://127.0.0.1:54324")!)
      #else
        await UIApplication.shared.open(URL(string: "http://127.0.0.1:54324")!)
      #endif
    } catch {
      toast = ToastState(status: .error, title: "Error", description: error.localizedDescription)
    }
  }
}

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
        Task { await model.signInButtonTapped() }
      }
    }
    .padding()
    .toast(state: $model.toast)
  }
}

#Preview {
  AuthView()
}
