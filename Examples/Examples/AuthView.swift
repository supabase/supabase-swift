//
//  AuthView.swift
//  Examples
//
//  Created by Guilherme Souza on 22/12/22.
//

import Auth
import SwiftUI

@Observable
@MainActor
final class AuthController {
  var session: Session?

  var currentUserID: UUID {
    guard let id = session?.user.id else {
      preconditionFailure("Required session.")
    }

    return id
  }

  @ObservationIgnored
  private var observeAuthStateChangesTask: Task<Void, Never>?

  init() {
    observeAuthStateChangesTask = Task {
      for await (event, session) in await supabase.auth.authStateChanges {
        guard event == .initialSession || event == .signedIn || event == .signedOut else {
          return
        }

        self.session = session
      }
    }
  }

  deinit {
    observeAuthStateChangesTask?.cancel()
  }
}

struct AuthView: View {
  enum Mode {
    case signIn, signUp
  }

  @Environment(AuthController.self) var auth

  @State var email = ""
  @State var password = ""
  @State var mode: Mode = .signIn
  @State var result: Result?

  enum Result {
    case failure(Error)
    case needsEmailConfirmation
  }

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

        if case .failure(let error) = result {
          ErrorText(error)
        }

        if case .needsEmailConfirmation = result {
          Text("Check you inbox.")
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
    .navigationTitle("Auth with Email & Password")
    .navigationBarTitleDisplayMode(.inline)
  }

  func primaryActionButtonTapped() async {
    do {
      result = nil
      switch mode {
      case .signIn:
        try await supabase.auth.signIn(email: email, password: password)
      case .signUp:
        let response = try await supabase.auth.signUp(
          email: email, password: password, redirectTo: URL(string: "com.supabase.Examples://")!
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
}

struct AuthView_Previews: PreviewProvider {
  static var previews: some View {
    AuthView()
  }
}
