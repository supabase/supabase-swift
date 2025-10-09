//
//  ResetPasswordView.swift
//  Examples
//
//  Demonstrates password reset functionality via email
//

import SwiftUI
import SwiftUINavigation

struct ResetPasswordView: View {
  @Environment(\.dismiss) private var dismiss

  @State private var email: String = ""
  @State private var actionState: ActionState<Void, Error> = .idle

  var body: some View {
    List {
      Section {
        Text("Enter your email address to receive a password reset link")
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Section("Email Address") {
        TextField("Enter your email", text: $email)
          .textContentType(.emailAddress)
          .autocorrectionDisabled()
          #if !os(macOS)
            .autocapitalization(.none)
            .keyboardType(.emailAddress)
          #endif
      }

      Section {
        Button("Send Reset Link") {
          Task {
            await resetPassword()
          }
        }
        .disabled(email.isEmpty)
      }

      switch actionState {
      case .idle:
        EmptyView()
      case .inFlight:
        Section {
          ProgressView("Sending reset link...")
        }
      case .result(.success):
        Section("Success") {
          VStack(alignment: .leading, spacing: 8) {
            Text("Password reset email sent successfully!")
              .foregroundColor(.green)

            Text("Check your inbox at \(email) for the reset link.")
              .font(.caption)
              .foregroundColor(.secondary)

            Text("The link will expire in 1 hour.")
              .font(.caption)
              .foregroundColor(.orange)
          }
        }
      case .result(.failure(let error)):
        Section {
          ErrorText(error)
        }
      }

      Section("About") {
        VStack(alignment: .leading, spacing: 8) {
          Text("Password Reset")
            .font(.headline)

          Text(
            "If you've forgotten your password, enter your email address to receive a secure password reset link. The link will be valid for 1 hour."
          )
          .font(.caption)
          .foregroundColor(.secondary)

          Text("How it works:")
            .font(.subheadline)
            .padding(.top, 4)

          VStack(alignment: .leading, spacing: 4) {
            Text("1. Enter your email address")
            Text("2. Click 'Send Reset Link'")
            Text("3. Check your email inbox")
            Text("4. Click the reset link in the email")
            Text("5. Enter your new password")
            Text("6. You're all set!")
          }
          .font(.caption)
          .foregroundColor(.secondary)

          Text("Security Notes:")
            .font(.subheadline)
            .padding(.top, 8)

          VStack(alignment: .leading, spacing: 4) {
            Label("Reset links expire after 1 hour", systemImage: "clock.fill")
            Label("Only the most recent link is valid", systemImage: "link.circle.fill")
            Label("Your old password remains valid until reset", systemImage: "lock.fill")
            Label(
              "You'll be signed out after password change", systemImage: "arrow.right.square.fill")
          }
          .font(.caption)
          .foregroundColor(.secondary)
        }
      }
    }
    .navigationTitle("Reset Password")
    .gitHubSourceLink()
    #if !os(macOS)
      .navigationBarTitleDisplayMode(.inline)
    #endif
  }

  func resetPassword() async {
    actionState = .inFlight

    do {
      try await supabase.auth.resetPasswordForEmail(email)
      actionState = .result(.success(()))
    } catch {
      actionState = .result(.failure(error))
    }
  }
}

#Preview {
  NavigationStack {
    ResetPasswordView()
  }
}
