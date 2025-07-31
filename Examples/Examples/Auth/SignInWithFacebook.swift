import FacebookLogin
import OSLog
import Supabase
import SwiftUI

struct SignInWithFacebook: View {
  @State private var actionState = ActionState<Void, Error>.idle

  static let logger = Logger(subsystem: "com.supabase.examples", category: "SignInWithFacebook")

  let loginManager = LoginManager()

  var body: some View {
    VStack {
      Button("Sign in with Facebook") {
        actionState = .inFlight

        loginManager.logIn(
          configuration: LoginConfiguration(
            permissions: ["public_profile", "email"],
            tracking: .limited
          )
        ) { result in
          switch result {
          case .failed(let error):
            actionState = .result(.failure(error))
            Self.logger.error("Facebook login failed: \(error.localizedDescription)")
          case .cancelled:
            actionState = .idle
            Self.logger.info("Facebook login cancelled")
          case .success(_, _, let token):
            Self.logger.info("Facebook login succeeded.")

            guard let idToken = token?.tokenString else {
              actionState = .idle
              Self.logger.error("Facebook login token is nil")
              return
            }

            Task {
              do {
                try await supabase.auth.signInWithIdToken(
                  credentials: OpenIDConnectCredentials(
                    provider: .facebook,
                    idToken: idToken
                  )
                )
                actionState = .result(.success(()))
                Self.logger.info("Successfully signed in with Facebook")
              } catch {
                actionState = .result(.failure(error))
                Self.logger.error("Failed to sign in with Facebook: \(error.localizedDescription)")

              }
            }
          }
        }
      }
    }
  }
}

#Preview {
  SignInWithFacebook()
}
