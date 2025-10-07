//
//  SignInWithApple.swift
//  Examples
//
//  Created by Guilherme Souza on 16/12/23.
//

import Auth
import AuthenticationServices
import SwiftUI

struct SignInWithApple: View {
  @State private var actionState = ActionState<Void, Error>.idle

  var body: some View {
    VStack {
      SignInWithAppleButton { request in
        request.requestedScopes = [.email, .fullName]
      } onCompletion: { result in
        switch result {
        case let .failure(error):
          debug("signInWithApple failed: \(error)")

        case let .success(authorization):
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

          Task {
            await signInWithApple(
              using: identityToken,
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
      case let .result(.failure(error)):
        ErrorText(error)
      }
    }
  }

  private func signInWithApple(using idToken: String, fullName: String?) async {
    actionState = .inFlight
    let result = await Result { @Sendable in
      _ = try await supabase.auth.signInWithIdToken(
        credentials: .init(
          provider: .apple,
          idToken: idToken
        ))

      // fullName is provided only in the first time (account creation),
      // so checking if it is non-nil to not erase data on login.
      if let fullName {
        _ = try? await supabase.auth.update(
          user: UserAttributes(data: ["full_name": .string(fullName)]))
      }
    }
    actionState = .result(result)
  }
}

#Preview {
  SignInWithApple()
}
