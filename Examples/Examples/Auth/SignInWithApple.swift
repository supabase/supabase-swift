//
//  SignInWithApple.swift
//  Examples
//
//  Created by Guilherme Souza on 16/12/23.
//

import AuthenticationServices
import Supabase
import SwiftUI

struct SignInWithApple: View {
  @Environment(\.supabase) private var supabase
  @State private var actionState = ActionState<Void, Error>.idle
  @State private var nonce: Nonce?

  var body: some View {
    VStack {
      SignInWithAppleButton { request in
        let nonce = Nonce.generate()
        self.nonce = nonce
        request.requestedScopes = [.email, .fullName]
        request.nonce = nonce.hashed
      } onCompletion: { result in
        switch result {
        case .failure(let error):
          debug("signInWithApple failed: \(error)")

        case .success(let authorization):
          guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential
          else {
            debug(
              "Invalid credential, expected \(ASAuthorizationAppleIDCredential.self) but got a \(type(of: authorization.credential))"
            )
            return
          }

          guard
            let identityToken = credential.identityToken.flatMap({
              String(
                data: $0,
                encoding: .utf8
              )
            })
          else {
            debug("Invalid identity token")
            return
          }

          guard let nonce else {
            debug("No nonce: the request was not configured")
            return
          }

          Task {
            await signInWithApple(
              using: identityToken,
              nonce: nonce.raw,
              fullName: credential.fullName?.formatted()
            )
          }
        }
      }
      .fixedSize()

      switch actionState {
      case .idle, .result(.success):
        EmptyView()
      case .inFlight:
        ProgressView()
      case .result(.failure(let error)):
        ErrorText(error)
      }
    }
    .gitHubSourceLink()
  }

  private func signInWithApple(
    using idToken: String,
    nonce: String,
    fullName: String?
  ) async {
    actionState = .inFlight
    let result = await Result { @Sendable in
      _ = try await supabase.auth.signInWithIDToken(
        IDTokenCredentials(
          provider: .apple,
          idToken: idToken,
          nonce: nonce
        ))

      // fullName is provided only in the first time (account creation),
      // so checking if it is non-nil to not erase data on login.
      if let fullName {
        _ = try? await supabase.auth.updateUser(
          UpdateUser(userMetadata: ["full_name": .string(fullName)]))
      }
    }
    actionState = .result(result)
  }
}

#Preview {
  SignInWithApple()
    .environment(\.supabase, supabaseClient)
}
