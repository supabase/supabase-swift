import SwiftUI

struct AuthView: View {
  @Environment(SessionStore.self) private var session

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
            submit { try await session.signIn(email: email, password: password) }
          }
          .accessibilityIdentifier("auth.signIn")
          Button("Create Account") {
            submit { try await session.signUp(email: email, password: password) }
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
