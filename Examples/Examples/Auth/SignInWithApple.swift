//
//  SignInWithApple.swift
//  Examples
//
//  Created by Guilherme Souza on 16/12/23.
//

import AuthenticationServices
import SwiftUI

struct SignInWithApple: View {
  @State private var actionState = ActionState<Void, Error>.idle

  var body: some View {
    VStack {
      SignInWithAppleButton { request in
        request.requestedScopes = [.email]
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

          guard let identityToken = credential.identityToken.flatMap({ String(
            data: $0,
            encoding: .utf8
          ) }) else {
            debug("Invalid identity token")
            return
          }

          Task {
            await signInWithApple(using: identityToken)
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

  private func signInWithApple(using idToken: String) async {
    actionState = .inFlight
    let result = await Result {
      _ = try await supabase.auth.signInWithIdToken(credentials: .init(
        provider: .apple,
        idToken: idToken
      ))
    }
    actionState = .result(result)
  }
}

#Preview {
  SignInWithApple()
}
