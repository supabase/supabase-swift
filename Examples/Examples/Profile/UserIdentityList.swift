//
//  UserIdentityList.swift
//  Examples
//
//  Demonstrates managing linked OAuth identities (social accounts)
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
  @State private var isLoading = false

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
        Section {
          Text(
            "Link multiple social accounts to your profile. You can sign in using any of your linked identities."
          )
          .font(.caption)
          .foregroundColor(.secondary)
        }

        if isLoading {
          Section {
            ProgressView("Loading...")
          }
        }

        if let error {
          Section {
            ErrorText(error)
          }
        }

        Section("Linked Identities (\(identities.count))") {
          if identities.isEmpty {
            VStack(spacing: 8) {
              Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.largeTitle)
                .foregroundColor(.secondary)

              Text("No identities linked yet")
                .font(.caption)
                .foregroundColor(.secondary)

              Text("Use the + button to link a social account")
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding()
          } else {
            ForEach(identities) { identity in
              VStack(alignment: .leading, spacing: 8) {
                HStack {
                  Image(systemName: iconForProvider(identity.provider))
                    .font(.title2)
                    .foregroundColor(.accentColor)
                    .frame(width: 40)

                  VStack(alignment: .leading, spacing: 4) {
                    Text(identity.provider.capitalized)
                      .font(.headline)

                    if let email = identity.identityData?["email"]?.stringValue {
                      Text(email)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }

                    if let createdAt = identity.createdAt {
                      HStack(spacing: 4) {
                        Image(systemName: "calendar")
                          .font(.caption2)
                        Text("Linked \(createdAt, style: .relative) ago")
                          .font(.caption2)
                      }
                      .foregroundColor(.secondary)
                    }
                  }

                  Spacer()
                }

                if let identityData = identity.identityData {
                  DisclosureGroup("Identity Data") {
                    AnyJSONView(value: .object(identityData))
                      .font(.system(.caption, design: .monospaced))
                  }
                  .font(.caption)
                }
              }
              .padding(.vertical, 4)
              .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                  Task {
                    await unlinkIdentity(identity)
                  }
                } label: {
                  Label("Unlink", systemImage: "link.badge.minus")
                }
              }
            }
          }
        }

        if !providers.isEmpty {
          Section("Available Providers") {
            ForEach(providers) { provider in
              Button {
                Task {
                  await linkProvider(provider)
                }
              } label: {
                HStack {
                  Image(systemName: iconForProvider(provider.rawValue))
                    .foregroundColor(.accentColor)
                  Text("Link \(provider.rawValue.capitalized)")
                  Spacer()
                  Image(systemName: "plus.circle.fill")
                    .foregroundColor(.green)
                }
              }
            }
          }
        }

        Section("Code Examples") {
          CodeExample(
            code: """
              // Get all linked identities
              let identities = try await supabase.auth.userIdentities()

              for identity in identities {
                print("Provider:", identity.provider)
                print("Email:", identity.identityData?["email"])
              }
              """
          )

          CodeExample(
            code: """
              // Link a new OAuth identity
              try await supabase.auth.linkIdentity(provider: .google)

              // For Apple, use OIDC flow
              try await supabase.auth.linkIdentityWithIdToken(
                credentials: OpenIDConnectCredentials(
                  provider: .apple,
                  idToken: appleIDToken
                )
              )
              """
          )

          CodeExample(
            code: """
              // Unlink an identity
              try await supabase.auth.unlinkIdentity(identity)

              // Note: You must have at least one way to sign in
              // (password, phone, or another linked identity)
              """
          )

          CodeExample(
            code: """
              // Get OAuth URL for manual flow
              let url = try supabase.auth.getLinkIdentityURL(
                provider: .github,
                redirectTo: URL(string: "your-app://auth-callback")
              )
              """
          )
        }

        Section("About") {
          VStack(alignment: .leading, spacing: 8) {
            Text("Linked Identities")
              .font(.headline)

            Text(
              "Linked identities allow you to sign in to your account using different social providers. Once linked, you can use any of these accounts to authenticate."
            )
            .font(.caption)
            .foregroundColor(.secondary)

            Text("Benefits:")
              .font(.subheadline)
              .padding(.top, 4)

            VStack(alignment: .leading, spacing: 4) {
              Label("Sign in with any linked account", systemImage: "checkmark.circle")
              Label("Consolidate multiple accounts", systemImage: "checkmark.circle")
              Label("Enhanced account recovery options", systemImage: "checkmark.circle")
              Label("Seamless cross-platform experience", systemImage: "checkmark.circle")
            }
            .font(.caption)
            .foregroundColor(.secondary)

            Text("Important:")
              .font(.subheadline)
              .padding(.top, 8)

            Text(
              "You must maintain at least one authentication method. You cannot unlink your last identity if you don't have a password or phone number set up."
            )
            .font(.caption)
            .foregroundColor(.orange)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(4)
          }
        }
      }
    }
    .id(id)
    .navigationTitle("Linked Identities")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        if !providers.isEmpty {
          Menu {
            ForEach(providers) { provider in
              Button {
                Task {
                  await linkProvider(provider)
                }
              } label: {
                Label(
                  provider.rawValue.capitalized,
                  systemImage: iconForProvider(provider.rawValue)
                )
              }
            }
          } label: {
            Label("Link Account", systemImage: "plus")
          }
        }
      }
    }
  }

  private func iconForProvider(_ provider: String) -> String {
    switch provider.lowercased() {
    case "google":
      return "g.circle.fill"
    case "apple":
      return "apple.logo"
    case "facebook":
      return "f.circle.fill"
    case "github":
      return "chevron.left.forwardslash.chevron.right"
    case "twitter", "x":
      return "x.circle.fill"
    case "discord":
      return "message.circle.fill"
    case "linkedin":
      return "link.circle.fill"
    default:
      return "person.crop.circle.fill"
    }
  }

  @MainActor
  private func linkProvider(_ provider: Provider) async {
    do {
      error = nil
      isLoading = true
      defer { isLoading = false }

      if provider == .apple {
        try await linkAppleIdentity()
      } else {
        try await supabase.auth.linkIdentity(provider: provider)
      }

      // Refresh the list
      id = UUID()
    } catch {
      self.error = error
    }
  }

  @MainActor
  private func unlinkIdentity(_ identity: UserIdentity) async {
    do {
      error = nil
      isLoading = true
      defer { isLoading = false }

      try await supabase.auth.unlinkIdentity(identity)

      // Refresh the list
      id = UUID()
    } catch {
      self.error = error
    }
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
  NavigationStack {
    UserIdentityList()
  }
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
