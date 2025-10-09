//
//  AuthWithEmailAndPassword.swift
//  Examples
//
//  Demonstrates email and password authentication with sign up and sign in
//

import SwiftUI

struct AuthWithEmailAndPassword: View {
  enum Mode {
    case signIn, signUp
  }

  enum Result {
    case needsEmailConfirmation
  }

  @Environment(AuthController.self) var auth

  @State var email = ""
  @State var password = ""
  @State var mode: Mode = .signIn
  @State var actionState = ActionState<Result, Error>.idle

  @State var isPresentingResetPassword: Bool = false

  var body: some View {
    List {
      Section {
        Text(
          mode == .signIn
            ? "Sign in with your email and password"
            : "Create a new account with email and password"
        )
        .font(.caption)
        .foregroundColor(.secondary)
      }

      Section("Credentials") {
        TextField("Email", text: $email)
          .textContentType(.emailAddress)
          .autocorrectionDisabled()
          #if !os(macOS)
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
          #endif

        SecureField("Password", text: $password)
          .textContentType(.password)
          .autocorrectionDisabled()
          #if !os(macOS)
            .textInputAutocapitalization(.never)
          #endif
      }

      Section {
        Button(mode == .signIn ? "Sign In" : "Sign Up") {
          Task {
            await primaryActionButtonTapped()
          }
        }
        .disabled(email.isEmpty || password.isEmpty)
      }

      switch actionState {
      case .idle:
        EmptyView()
      case .inFlight:
        Section {
          ProgressView(mode == .signIn ? "Signing in..." : "Creating account...")
        }
      case .result(.failure(let error)):
        Section {
          ErrorText(error)
        }
      case .result(.success(.needsEmailConfirmation)):
        Section("Email Confirmation Required") {
          Text("Check your inbox for a confirmation email.")
            .foregroundColor(.green)

          Button("Resend Confirmation") {
            Task {
              await resendConfirmationButtonTapped()
            }
          }
        }
      }

      Section {
        Button(
          mode == .signIn
            ? "Don't have an account? Sign up."
            : "Already have an account? Sign in."
        ) {
          mode = mode == .signIn ? .signUp : .signIn
          actionState = .idle
        }
      }

      if mode == .signIn {
        Section {
          Button("Forgot password? Reset it.") {
            isPresentingResetPassword = true
          }
        }
      }

      Section("Code Examples") {
        CodeExample(
          code: """
            // Sign up with email and password
            let response = try await supabase.auth.signUp(
              email: "\(email.isEmpty ? "user@example.com" : email)",
              password: "\(password.isEmpty ? "your-password" : "********")",
              redirectTo: URL(string: "your-app://auth-callback")
            )

            // Check if email confirmation is required
            if case .user = response {
              print("Please check your email for confirmation")
            }
            """
        )

        CodeExample(
          code: """
            // Sign in with email and password
            try await supabase.auth.signIn(
              email: "\(email.isEmpty ? "user@example.com" : email)",
              password: "\(password.isEmpty ? "your-password" : "********")"
            )
            """
        )

        CodeExample(
          code: """
            // Resend email confirmation
            try await supabase.auth.resend(
              email: "\(email.isEmpty ? "user@example.com" : email)",
              type: .signup
            )
            """
        )
      }

      Section("About") {
        VStack(alignment: .leading, spacing: 8) {
          Text("Email & Password Authentication")
            .font(.headline)

          Text(
            "Email and password authentication is the most common method. Users can sign up with their email and a secure password, then sign in with those credentials."
          )
          .font(.caption)
          .foregroundColor(.secondary)

          Text("Features:")
            .font(.subheadline)
            .padding(.top, 4)

          VStack(alignment: .leading, spacing: 4) {
            Label("Email confirmation via link", systemImage: "checkmark.circle")
            Label("Password requirements enforcement", systemImage: "checkmark.circle")
            Label("Password reset functionality", systemImage: "checkmark.circle")
            Label("Secure session management", systemImage: "checkmark.circle")
          }
          .font(.caption)
          .foregroundColor(.secondary)
        }
      }
    }
    .navigationTitle("Email & Password")
    .onOpenURL { url in
      Task {
        await onOpenURL(url)
      }
    }
    .animation(.default, value: mode)
    .sheet(isPresented: $isPresentingResetPassword) {
      ResetPasswordView()
    }
  }

  @MainActor
  func primaryActionButtonTapped() async {
    do {
      actionState = .inFlight
      switch mode {
      case .signIn:
        try await supabase.auth.signIn(email: email, password: password)
      case .signUp:
        let response = try await supabase.auth.signUp(
          email: email,
          password: password,
          redirectTo: Constants.redirectToURL
        )

        if case .user = response {
          actionState = .result(.success(.needsEmailConfirmation))
        }
      }
    } catch {
      withAnimation {
        actionState = .result(.failure(error))
      }
    }
  }

  @MainActor
  private func onOpenURL(_ url: URL) async {
    do {
      try await supabase.auth.session(from: url)
    } catch {
      debug("Fail to init session with url: \(url)")
    }
  }

  @MainActor
  private func resendConfirmationButtonTapped() async {
    do {
      try await supabase.auth.resend(email: email, type: .signup)
    } catch {
      debug("Fail to resend email confirmation: \(error)")
    }
  }
}

#Preview {
  AuthWithEmailAndPassword()
    .environment(AuthController())
}
