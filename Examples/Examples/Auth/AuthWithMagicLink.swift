//
//  AuthWithMagicLink.swift
//  Examples
//
//  Demonstrates passwordless authentication using magic links sent via email
//

import SwiftUI

struct AuthWithMagicLink: View {
  @State var email = ""
  @State var actionState: ActionState<Void, Error> = .idle
  @State var successMessage: String?

  var body: some View {
    List {
      Section {
        Text("Sign in without a password. A magic link will be sent to your email.")
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Section("Email Address") {
        TextField("Email", text: $email)
          .textContentType(.emailAddress)
          .autocorrectionDisabled()
          #if !os(macOS)
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
          #endif
      }

      Section {
        Button("Send Magic Link") {
          Task {
            await signInWithMagicLinkTapped()
          }
        }
        .disabled(email.isEmpty)
      }

      switch actionState {
      case .idle:
        EmptyView()
      case .inFlight:
        Section {
          ProgressView("Sending magic link...")
        }
      case .result(.success):
        Section("Success") {
          Text("Magic link sent! Check your email inbox.")
            .foregroundColor(.green)

          Text("Click the link in your email to sign in automatically.")
            .font(.caption)
            .foregroundColor(.secondary)
        }
      case .result(.failure(let error)):
        Section {
          ErrorText(error)
        }
      }

      Section("About") {
        VStack(alignment: .leading, spacing: 8) {
          Text("Magic Link Authentication")
            .font(.headline)

          Text(
            "Magic links provide a passwordless authentication experience. Users receive an email with a secure link that automatically signs them in when clicked."
          )
          .font(.caption)
          .foregroundColor(.secondary)

          Text("Benefits:")
            .font(.subheadline)
            .padding(.top, 4)

          VStack(alignment: .leading, spacing: 4) {
            Label("No password to remember", systemImage: "checkmark.circle")
            Label("Enhanced security", systemImage: "checkmark.circle")
            Label("Better user experience", systemImage: "checkmark.circle")
            Label("Reduced support requests", systemImage: "checkmark.circle")
          }
          .font(.caption)
          .foregroundColor(.secondary)

          Text("How it works:")
            .font(.subheadline)
            .padding(.top, 8)

          VStack(alignment: .leading, spacing: 4) {
            Text("1. User enters their email address")
            Text("2. Supabase sends a secure one-time link")
            Text("3. User clicks the link in their email")
            Text("4. App handles the URL and creates a session")
          }
          .font(.caption)
          .foregroundColor(.secondary)
        }
      }
    }
    .navigationTitle("Magic Link")
    .gitHubSourceLink()
    .onOpenURL { url in
      Task { await onOpenURL(url) }
    }
  }

  private func signInWithMagicLinkTapped() async {
    actionState = .inFlight

    actionState = await .result(
      Result { @Sendable in
        try await supabase.auth.signInWithOTP(
          email: email,
          redirectTo: Constants.redirectToURL
        )
      }
    )
  }

  private func onOpenURL(_ url: URL) async {
    debug("received url: \(url)")

    actionState = .inFlight
    actionState = await .result(
      Result { @Sendable in
        try await supabase.auth.session(from: url)
      }
    )
  }
}

#Preview {
  AuthWithMagicLink()
}
