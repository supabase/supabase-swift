//
//  MFAFlow.swift
//  Examples
//
//  Demonstrates multi-factor authentication (MFA) enrollment, verification, and management
//

import SVGView
import Supabase
import SwiftUI

enum MFAStatus {
  case unenrolled
  case unverified
  case verified
  case disabled

  var description: String {
    switch self {
    case .unenrolled:
      "User does not have MFA enrolled."
    case .unverified:
      "User has an MFA factor enrolled but has not verified it."
    case .verified:
      "User has verified their MFA factor."
    case .disabled:
      "User has disabled their MFA factor. (Stale JWT.)"
    }
  }
}

struct MFAFlow: View {
  let status: MFAStatus

  var body: some View {
    NavigationStack {
      switch status {
      case .unenrolled:
        MFAEnrollView()
      case .unverified:
        MFAVerifyView()
      case .verified:
        MFAVerifiedView()
      case .disabled:
        MFADisabledView()
      }
    }
  }
}

struct MFAEnrollView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var verificationCode = ""

  @State private var enrollResponse: AuthMFAEnrollResponse?
  @State private var error: Error?
  @State private var isLoading = false

  var body: some View {
    List {
      Section {
        Text("Set up two-factor authentication using a TOTP authenticator app")
          .font(.caption)
          .foregroundColor(.secondary)
      }

      if let totp = enrollResponse?.totp {
        Section("QR Code") {
          VStack(spacing: 12) {
            SVGView(string: totp.qrCode)
              .frame(width: 200, height: 200)

            Text("Scan this QR code with your authenticator app")
              .font(.caption)
              .foregroundColor(.secondary)
              .multilineTextAlignment(.center)
          }
          .frame(maxWidth: .infinity)
        }

        Section("Manual Entry") {
          VStack(alignment: .leading, spacing: 8) {
            Text("Secret Key")
              .font(.caption)
              .foregroundColor(.secondary)
            Text(totp.secret)
              .font(.system(.body, design: .monospaced))
              .textSelection(.enabled)

            Text("URI")
              .font(.caption)
              .foregroundColor(.secondary)
              .padding(.top, 4)
            Text(totp.uri)
              .font(.system(.caption, design: .monospaced))
              .textSelection(.enabled)
              .lineLimit(3)
          }
        }
      }

      Section("Verification Code") {
        TextField("Enter 6-digit code", text: $verificationCode)
          .textContentType(.oneTimeCode)
          .autocorrectionDisabled()
          #if !os(macOS)
            .keyboardType(.numberPad)
            .textInputAutocapitalization(.never)
          #endif

        Text("Enter the code from your authenticator app")
          .font(.caption)
          .foregroundColor(.secondary)
      }

      if isLoading {
        Section {
          ProgressView("Enrolling MFA...")
        }
      }

      if let error {
        Section {
          ErrorText(error)
        }
      }

      Section("Code Examples") {
        CodeExample(
          code: """
            // Enroll in MFA
            let response = try await supabase.auth.mfa.enroll(
              params: MFAEnrollParams()
            )

            // response.totp contains:
            // - qrCode: SVG string for QR code
            // - secret: Secret key for manual entry
            // - uri: URI for authenticator apps
            """
        )

        CodeExample(
          code: """
            // Verify the enrollment
            try await supabase.auth.mfa.challengeAndVerify(
              params: MFAChallengeAndVerifyParams(
                factorId: response.id,
                code: "123456"
              )
            )
            """
        )
      }

      Section("About") {
        VStack(alignment: .leading, spacing: 8) {
          Text("Multi-Factor Authentication")
            .font(.headline)

          Text(
            "MFA adds an extra layer of security by requiring a second form of verification in addition to your password. Use any TOTP-compatible authenticator app."
          )
          .font(.caption)
          .foregroundColor(.secondary)

          Text("Compatible Apps:")
            .font(.subheadline)
            .padding(.top, 4)

          VStack(alignment: .leading, spacing: 4) {
            Label("Google Authenticator", systemImage: "checkmark.circle")
            Label("Authy", systemImage: "checkmark.circle")
            Label("1Password", systemImage: "checkmark.circle")
            Label("Microsoft Authenticator", systemImage: "checkmark.circle")
          }
          .font(.caption)
          .foregroundColor(.secondary)
        }
      }
    }
    .navigationTitle("Enroll MFA")
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel", role: .cancel) {
          dismiss()
        }
      }

      ToolbarItem(placement: .primaryAction) {
        Button("Enable") {
          enableButtonTapped()
        }
        .disabled(verificationCode.isEmpty || isLoading)
      }
    }
    .task {
      await enrollMFA()
    }
  }

  @MainActor
  private func enrollMFA() async {
    do {
      error = nil
      isLoading = true
      defer { isLoading = false }

      enrollResponse = try await supabase.auth.mfa.enroll(params: .totp())
    } catch {
      self.error = error
    }
  }

  @MainActor
  private func enableButtonTapped() {
    Task {
      do {
        error = nil
        isLoading = true
        defer { isLoading = false }

        try await supabase.auth.mfa.challengeAndVerify(
          params: MFAChallengeAndVerifyParams(factorId: enrollResponse!.id, code: verificationCode)
        )
        dismiss()
      } catch {
        self.error = error
      }
    }
  }
}

struct MFAVerifyView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var verificationCode = ""
  @State private var error: Error?
  @State private var isLoading = false

  var body: some View {
    List {
      Section {
        Text("Enter the verification code from your authenticator app to sign in")
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Section("Verification Code") {
        TextField("6-digit code", text: $verificationCode)
          .textContentType(.oneTimeCode)
          .autocorrectionDisabled()
          #if !os(macOS)
            .keyboardType(.numberPad)
            .textInputAutocapitalization(.never)
          #endif
      }

      if isLoading {
        Section {
          ProgressView("Verifying code...")
        }
      }

      if let error {
        Section {
          ErrorText(error)
        }
      }

      Section("Code Examples") {
        CodeExample(
          code: """
            // List all MFA factors
            let factors = try await supabase.auth.mfa.listFactors()

            // Get the TOTP factor
            guard let totpFactor = factors.totp.first else {
              return
            }

            // Verify with code from authenticator app
            try await supabase.auth.mfa.challengeAndVerify(
              params: MFAChallengeAndVerifyParams(
                factorId: totpFactor.id,
                code: "123456"
              )
            )
            """
        )
      }

      Section("About") {
        VStack(alignment: .leading, spacing: 8) {
          Text("MFA Verification Required")
            .font(.headline)

          Text(
            "Your account has MFA enabled. Please enter the 6-digit code from your authenticator app to complete sign in."
          )
          .font(.caption)
          .foregroundColor(.secondary)
        }
      }
    }
    .navigationTitle("Verify MFA")
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel", role: .cancel) {
          dismiss()
        }
      }

      ToolbarItem(placement: .primaryAction) {
        Button("Verify") {
          verifyButtonTapped()
        }
        .disabled(verificationCode.isEmpty || isLoading)
      }
    }
  }

  @MainActor
  private func verifyButtonTapped() {
    Task {
      do {
        error = nil
        isLoading = true
        defer { isLoading = false }

        let factors = try await supabase.auth.mfa.listFactors()
        guard let totpFactor = factors.totp.first else {
          debugPrint("No TOTP factor found.")
          return
        }

        try await supabase.auth.mfa.challengeAndVerify(
          params: MFAChallengeAndVerifyParams(factorId: totpFactor.id, code: verificationCode)
        )
        dismiss()
      } catch {
        self.error = error
      }
    }
  }
}

struct MFAVerifiedView: View {
  @Environment(AuthController.self) var auth

  @MainActor
  var factors: [Factor] {
    auth.session?.user.factors ?? []
  }

  var body: some View {
    List {
      Section {
        Text("Manage your multi-factor authentication settings")
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Section("Active MFA Factors") {
        if factors.isEmpty {
          Text("No MFA factors enrolled")
            .font(.caption)
            .foregroundColor(.secondary)
        } else {
          ForEach(factors) { factor in
            VStack(alignment: .leading, spacing: 8) {
              HStack {
                Image(systemName: "checkmark.shield.fill")
                  .foregroundColor(.green)

                VStack(alignment: .leading, spacing: 2) {
                  Text(factor.friendlyName ?? "TOTP Factor")
                    .font(.headline)
                  Text("Status: \(factor.status.rawValue)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
              }

              VStack(alignment: .leading, spacing: 4) {
                HStack {
                  Text("ID:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                  Text(factor.id)
                    .font(.system(.caption, design: .monospaced))
                }

                HStack {
                  Text("Type:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                  Text(factor.factorType)
                    .font(.caption)
                }
              }
              .padding(.top, 4)
            }
            .padding(.vertical, 4)
          }
          .onDelete { indexSet in
            Task {
              await deleteFactor(at: indexSet)
            }
          }
        }
      }

      Section("Code Examples") {
        CodeExample(
          code: """
            // List all MFA factors
            let factors = try await supabase.auth.mfa.listFactors()

            // Access current user's factors
            let userFactors = supabase.auth.session?.user.factors
            """
        )

        CodeExample(
          code: """
            // Unenroll (remove) an MFA factor
            try await supabase.auth.mfa.unenroll(
              params: MFAUnenrollParams(factorId: factor.id)
            )
            """
        )
      }

      Section("About") {
        VStack(alignment: .leading, spacing: 8) {
          Text("MFA Factor Management")
            .font(.headline)

          Text(
            "You can manage your enrolled MFA factors here. Swipe left on a factor to remove it. Each factor provides an additional layer of security for your account."
          )
          .font(.caption)
          .foregroundColor(.secondary)

          Text("Security Tips:")
            .font(.subheadline)
            .padding(.top, 4)

          VStack(alignment: .leading, spacing: 4) {
            Label("Keep your authenticator app secure", systemImage: "lock.fill")
            Label("Back up your secret keys safely", systemImage: "key.fill")
            Label("Don't share verification codes", systemImage: "eye.slash.fill")
            Label("Consider multiple factors for backup", systemImage: "plus.circle.fill")
          }
          .font(.caption)
          .foregroundColor(.secondary)
        }
      }
    }
    .navigationTitle("MFA Settings")
  }

  @MainActor
  private func deleteFactor(at indexSet: IndexSet) async {
    do {
      let factorsToRemove = indexSet.map { factors[$0] }
      for factor in factorsToRemove {
        try await supabase.auth.mfa.unenroll(params: MFAUnenrollParams(factorId: factor.id))
      }
    } catch {
      debug("Failed to unenroll factor: \(error)")
    }
  }
}

struct MFADisabledView: View {
  var body: some View {
    List {
      Section {
        Text(MFAStatus.disabled.description)
          .foregroundColor(.orange)
      }

      Section("Code Examples") {
        CodeExample(
          code: """
            // Re-authenticate to refresh JWT
            try await supabase.auth.refreshSession()
            """
        )
      }

      Section("About") {
        VStack(alignment: .leading, spacing: 8) {
          Text("MFA Disabled")
            .font(.headline)

          Text(
            "Your MFA factor has been disabled. This typically happens when your authentication token (JWT) is stale. Please refresh your session to re-enable MFA."
          )
          .font(.caption)
          .foregroundColor(.secondary)
        }
      }
    }
    .navigationTitle("MFA Disabled")
  }
}
