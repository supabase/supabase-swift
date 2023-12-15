//
//  AuthWithEmailAndPassword.swift
//  Examples
//
//  Created by Guilherme Souza on 15/12/23.
//

import SwiftUI

struct AuthWithEmailAndPassword: View {
  enum Mode {
    case signIn, signUp
  }

  enum Result {
    case failure(Error)
    case needsEmailConfirmation
  }

  @Environment(AuthController.self) var auth

  @State var email = ""
  @State var password = ""
  @State var mode: Mode = .signIn
  @State var result: Result?

  var body: some View {
    Form {
      Section {
        TextField("Email", text: $email)
          .keyboardType(.emailAddress)
          .textContentType(.emailAddress)
          .autocorrectionDisabled()
          .textInputAutocapitalization(.never)
        SecureField("Password", text: $password)
          .textContentType(.password)
          .autocorrectionDisabled()
          .textInputAutocapitalization(.never)
        Button(mode == .signIn ? "Sign in" : "Sign up") {
          Task {
            await primaryActionButtonTapped()
          }
        }

        if case let .failure(error) = result {
          ErrorText(error)
        }
      }

      if mode == .signUp, case .needsEmailConfirmation = result {
        Section {
          Text("Check you inbox.")

          Button("Resend confirmation") {
            Task {
              await resendConfirmationButtonTapped()
            }
          }
        }
      }

      Section {
        Button(
          mode == .signIn ? "Don't have an account? Sign up." : "Already have an account? Sign in."
        ) {
          withAnimation {
            mode = mode == .signIn ? .signUp : .signIn
            result = nil
          }
        }
      }
    }
  }

  func primaryActionButtonTapped() async {
    do {
      result = nil
      switch mode {
      case .signIn:
        try await supabase.auth.signIn(email: email, password: password)
      case .signUp:
        let response = try await supabase.auth.signUp(
          email: email, password: password, redirectTo: URL(string: "com.supabase.Examples://")
        )

        if case .user = response {
          result = .needsEmailConfirmation
        }
      }
    } catch {
      withAnimation {
        result = .failure(error)
      }
    }
  }

  private func resendConfirmationButtonTapped() async {
    do {
      try await supabase.auth.resend(email: email, type: .signup)
    } catch {
      debug("Fail to resend email confirmation: \(error)")
    }
  }
}

#Preview {
  AuthWithEmailAndPassword()
}
