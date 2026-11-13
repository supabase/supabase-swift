import Supabase
import SwiftUI

struct AuthView: View {
  @Environment(\.supabase) private var client

  @State private var email = ""
  @State private var password = ""
  @State private var isWorking = false
  @State private var errorText: String?

  private var canSubmit: Bool {
    !email.isEmpty && password.count >= 6 && !isWorking
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("Email", text: $email)
            .textContentType(.username)
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .accessibilityIdentifier("auth.email")
          SecureField("Password", text: $password)
            .textContentType(.password)
            .accessibilityIdentifier("auth.password")
        } footer: {
          if let errorText {
            Text(errorText)
              .foregroundStyle(.red)
              .accessibilityIdentifier("auth.error")
          }
        }

        Section {
          Button("Sign In") {
            submit { try await client.auth.signIn(email: email, password: password) }
          }
          .accessibilityIdentifier("auth.signIn")
          Button("Create Account") {
            // The local project needs no email confirmation, so a new account is
            // signed in at once. `AuthModel` reports the new session.
            submit { _ = try await client.auth.signUp(email: email, password: password) }
          }
          .accessibilityIdentifier("auth.signUp")
        }
        .disabled(!canSubmit)
      }
      .navigationTitle("Reminders")
    }
  }

  private func submit(_ action: @escaping () async throws -> Void) {
    isWorking = true
    errorText = nil
    Task {
      do {
        try await action()
      } catch {
        errorText = errorMessage(for: error)
      }
      isWorking = false
    }
  }
}
