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
    case needsEmailConfirmation
  }

  @Environment(AuthController.self) var auth

  @State var email = ""
  @State var password = ""
  @State var mode: Mode = .signIn
  @State var actionState = ActionState<Result, Error>.idle

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
      }

      Section {
        Button(mode == .signIn ? "Sign in" : "Sign up") {
          Task {
            await primaryActionButtonTapped()
          }
        }
      }

      switch actionState {
      case .idle:
        EmptyView()
      case .inFlight:
        ProgressView()
      case let .result(.failure(error)):
        ErrorText(error)
      case .result(.success(.needsEmailConfirmation)):
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
          mode = mode == .signIn ? .signUp : .signIn
          actionState = .idle
        }
      }
    }
    .onOpenURL { url in
      Task {
        await onOpenURL(url)
      }
    }
    .animation(.default, value: mode)
  }

  @MainActor
  func primaryActionButtonTapped() async {
    do {
      actionState = .inFlight
      switch mode {
      case .signIn:
        try await supabase.auth.signIn(email: email, password: password)
      case .signUp:
        let response = try await supabase.auth.signUp(
          email: email,
          password: password,
          redirectTo: Constants.redirectToURL
        )

        if case .user = response {
          actionState = .result(.success(.needsEmailConfirmation))
        }
      }
    } catch {
      withAnimation {
        actionState = .result(.failure(error))
      }
    }
  }

  @MainActor
  private func onOpenURL(_ url: URL) async {
    do {
      try await supabase.auth.session(from: url)
    } catch {
      debug("Fail to init session with url: \(url)")
    }
  }

  @MainActor
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
    .environment(AuthController())
}
