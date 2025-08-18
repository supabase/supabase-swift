//
//  UserIdentityList.swift
//  Examples
//
//  Created by Guilherme Souza on 22/03/24.
//

import AuthenticationServices
import Supabase
import SwiftUI

struct UserIdentityList: View {
  @Environment(\.webAuthenticationSession) private var webAuthenticationSession
  @Environment(\.openURL) private var openURL

  @State private var identities = ActionState<[UserIdentity], any Error>.idle
  @State private var error: (any Error)?
  @State private var id = UUID()

  private var providers: [Provider] {
    let allProviders = Provider.allCases
    let identities = identities.success ?? []

    return allProviders.filter { provider in
      !identities.contains(where: { $0.provider == provider.rawValue })
    }
  }

  var body: some View {
    ActionStateView(state: $identities) {
      try await supabase.auth.userIdentities()
    } content: { identities in
      List {
        if let error {
          ErrorText(error)
        }

        ForEach(identities) { identity in
          Section {
            AnyJSONView(value: try! AnyJSON(identity))
          } footer: {
            Button("Unlink") {
              Task {
                do {
                  error = nil
                  try await supabase.auth.unlinkIdentity(identity)
                  id = UUID()
                } catch {
                  self.error = error
                }
              }
            }
          }
        }
      }
    }
    .id(id)
    #if swift(>=5.10)
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Menu("Add") {
            ForEach(providers) { provider in
              Button(provider.rawValue) {
                Task {
                  do {
                    if provider == .apple {
                      try await linkAppleIdentity()
                    } else {
                      try await supabase.auth.linkIdentity(provider: provider)
                    }
                  } catch {
                    self.error = error
                  }
                }
              }
            }
          }
        }
      }
    #endif
  }

  private func linkAppleIdentity() async throws {
    let provider = ASAuthorizationAppleIDProvider()
    let request = provider.createRequest()
    request.requestedScopes = [.email, .fullName]

    let controller = ASAuthorizationController(authorizationRequests: [request])
    let authorization = try await controller.performRequests()

    guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
      debug("Invalid credential")
      return
    }

    guard
      let identityToken = credential.identityToken.flatMap({ String(data: $0, encoding: .utf8) })
    else {
      debug("Invalid identity token")
      return
    }

    try await supabase.auth.linkIdentityWithIdToken(
      credentials: OpenIDConnectCredentials(
        provider: .apple,
        idToken: identityToken
      )
    )
  }
}

#Preview {
  UserIdentityList()
}

extension ASAuthorizationController {
  @MainActor
  func performRequests() async throws -> ASAuthorization {
    let delegate = _Delegate()
    self.delegate = delegate
    return try await withCheckedThrowingContinuation { continuation in
      delegate.continuation = continuation

      self.performRequests()
    }
  }

  private final class _Delegate: NSObject, ASAuthorizationControllerDelegate {
    var continuation: CheckedContinuation<ASAuthorization, any Error>?

    func authorizationController(
      controller: ASAuthorizationController,
      didCompleteWithAuthorization authorization: ASAuthorization
    ) {
      continuation?.resume(returning: authorization)
    }

    func authorizationController(
      controller: ASAuthorizationController,
      didCompleteWithError error: any Error
    ) {
      continuation?.resume(throwing: error)
    }
  }
}
