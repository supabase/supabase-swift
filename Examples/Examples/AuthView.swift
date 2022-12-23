//
//  AuthView.swift
//  Examples
//
//  Created by Guilherme Souza on 22/12/22.
//

import GoTrue
import SwiftUI

final class AuthController: ObservableObject {
  @Published var session: Session?

  var currentUserID: UUID {
    guard let id = session?.user.id else {
      preconditionFailure("Required session.")
    }

    return id
  }
}

struct AuthView: View {
  enum Mode {
    case signIn, signUp
  }

  @EnvironmentObject var auth: AuthController

  @State var email = ""
  @State var password = ""
  @State var mode: Mode = .signIn
  @State var error: Error?

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

        if let error {
          ErrorText(error)
        }
      }

      Section {
        Button(
          mode == .signIn ? "Don't have an account? Sign up." :
            "Already have an account? Sign in."
        ) {
          withAnimation {
            mode = mode == .signIn ? .signUp : .signIn
          }
        }
      }
    }
  }

  func primaryActionButtonTapped() async {
    do {
      error = nil
      switch mode {
      case .signIn:
        try await supabase.auth.signIn(email: email, password: password)
      case .signUp:
        try await supabase.auth.signUp(email: email, password: password)
      }
    } catch {
      withAnimation {
        self.error = error
      }
    }
  }
}

struct AuthView_Previews: PreviewProvider {
  static var previews: some View {
    AuthView()
  }
}
