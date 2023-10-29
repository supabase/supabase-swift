//
//  AuthView.swift
//  Examples
//
//  Created by Guilherme Souza on 22/12/22.
//

import GoTrue
import SwiftUI

@MainActor
final class AuthViewModel: ObservableObject {
  enum Mode {
    case signIn, signUp
  }

  @Published var email = ""
  @Published var password = ""
  @Published var mode: Mode = .signIn
  @Published var authError: Error?

  func signInButtonTapped() async {
    do {
      authError = nil
      try await supabase.auth.signIn(email: email, password: password)
    } catch {
      logger.error("signIn: \(error.localizedDescription)")
      self.authError = error
    }
  }

  func signUpButtonTapped() async {
    do {
      authError = nil
      try await supabase.auth.signUp(
        email: email, password: password, redirectTo: URL(string: "com.supabase.Examples://")!)
    } catch {
      logger.error("signUp: \(error.localizedDescription)")
      self.authError = error
    }
  }
}

struct AuthView: View {
  @ObservedObject var model: AuthViewModel

  var body: some View {
    Form {
      Section {
        TextField("Email", text: $model.email)
          .keyboardType(.emailAddress)
          .textContentType(.emailAddress)
          .autocorrectionDisabled()
          .textInputAutocapitalization(.never)
        SecureField("Password", text: $model.password)
          .textContentType(.password)
          .autocorrectionDisabled()
          .textInputAutocapitalization(.never)
        AsyncButton(model.mode == .signIn ? "Sign in" : "Sign up") {
          await primaryActionButtonTapped()
        }

        if let error = model.authError {
          ErrorText(error)
        }
      }

      Section {
        Button(
          model.mode == .signIn ? "Don't have an account? Sign up." : "Already have an account? Sign in."
        ) {
          withAnimation {
            model.mode = model.mode == .signIn ? .signUp : .signIn
          }
        }
      }
    }
  }

  func primaryActionButtonTapped() async {
    switch model.mode {
    case .signIn:
      await model.signInButtonTapped()
    case .signUp:
      await model.signUpButtonTapped()
    }
  }
}
