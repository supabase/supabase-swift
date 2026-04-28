//
//  ProfileView.swift
//  Examples
//
//  Demonstrates user profile management and account operations
//

import Supabase
import SwiftUI

#if canImport(LocalAuthentication)
  import LocalAuthentication
#endif

struct ProfileView: View {
  @State var user: User?
  @State var error: Error?
  @State var isLoading = false
  @State var showingMFA = false
  @State var showingBiometrics = false

  var identities: [UserIdentity] {
    user?.identities ?? []
  }

  var mfaFactors: [Factor] {
    user?.factors ?? []
  }

  var body: some View {
    NavigationStack {
      List {
        Section {
          Text("Manage your account, profile information, and security settings")
            .font(.caption)
            .foregroundColor(.secondary)
        }

        if isLoading {
          Section {
            ProgressView("Loading profile...")
          }
        }

        if let error {
          Section {
            ErrorText(error)
          }
        }

        // User Information
        if let user {
          Section("Account Information") {
            VStack(alignment: .leading, spacing: 8) {
              if let email = user.email {
                HStack {
                  Image(systemName: "envelope.fill")
                    .foregroundColor(.accentColor)
                  VStack(alignment: .leading, spacing: 2) {
                    Text("Email")
                      .font(.caption)
                      .foregroundColor(.secondary)
                    Text(email)
                      .font(.subheadline)
                  }
                }
              }

              if let phone = user.phone {
                HStack {
                  Image(systemName: "phone.fill")
                    .foregroundColor(.accentColor)
                  VStack(alignment: .leading, spacing: 2) {
                    Text("Phone")
                      .font(.caption)
                      .foregroundColor(.secondary)
                    Text(phone)
                      .font(.subheadline)
                  }
                }
                .padding(.top, 4)
              }

              HStack {
                Image(systemName: "person.fill")
                  .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                  Text("User ID")
                    .font(.caption)
                    .foregroundColor(.secondary)
                  Text(user.id.uuidString)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                }
              }
              .padding(.top, 4)

              HStack {
                Image(systemName: "calendar")
                  .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                  Text("Created")
                    .font(.caption)
                    .foregroundColor(.secondary)
                  Text(user.createdAt, style: .date)
                    .font(.caption)
                }
              }
              .padding(.top, 4)
            }
            .padding(.vertical, 4)
          }

          // Profile Management
          Section("Profile Management") {
            NavigationLink {
              UpdateProfileView(user: user)
            } label: {
              Label("Update Profile", systemImage: "pencil.circle.fill")
            }

            NavigationLink {
              ResetPasswordView()
            } label: {
              Label("Change Password", systemImage: "key.fill")
            }
          }

          // Security Section
          Section("Security") {
            #if canImport(LocalAuthentication)
              BiometricsRow(showingBiometrics: $showingBiometrics, error: $error)
            #endif

            HStack {
              Label("Multi-Factor Auth", systemImage: "lock.shield.fill")
              Spacer()
              if mfaFactors.isEmpty {
                Text("Not Enabled")
                  .font(.caption)
                  .foregroundColor(.secondary)
              } else {
                Text("\(mfaFactors.count) Factor(s)")
                  .font(.caption)
                  .foregroundColor(.green)
              }
            }
            .onTapGesture {
              showingMFA = true
            }

            Button {
              Task {
                await reauthenticate()
              }
            } label: {
              Label("Reauthenticate", systemImage: "arrow.clockwise.circle.fill")
            }
          }

          // Linked Identities
          Section("Linked Accounts") {
            NavigationLink {
              UserIdentityList()
            } label: {
              HStack {
                Label("Manage Identities", systemImage: "link.circle.fill")
                Spacer()
                Text("\(identities.count)")
                  .font(.caption)
                  .foregroundColor(.secondary)
              }
            }

            if identities.count > 1 {
              Menu {
                ForEach(identities) { identity in
                  Button(role: .destructive) {
                    Task {
                      await unlinkIdentity(identity)
                    }
                  } label: {
                    Label("Unlink \(identity.provider)", systemImage: "link.badge.minus")
                  }
                }
              } label: {
                Label("Unlink Identity", systemImage: "link.badge.minus")
                  .foregroundColor(.orange)
              }
            }
          }

          // Raw User Data
          Section("User Data (JSON)") {
            if let json = try? AnyJSON(user) {
              AnyJSONView(value: json)
            }
          }
        }

        // Sign Out
        Section {
          Button(role: .destructive) {
            Task {
              await signOut()
            }
          } label: {
            HStack {
              Spacer()
              Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
              Spacer()
            }
          }
        }

        Section("About") {
          VStack(alignment: .leading, spacing: 8) {
            Text("Profile Management")
              .font(.headline)

            Text(
              "Your profile contains all account information and settings. You can update your email, phone, password, manage linked accounts, and configure security options like MFA."
            )
            .font(.caption)
            .foregroundColor(.secondary)

            Text("Available Actions:")
              .font(.subheadline)
              .padding(.top, 4)

            VStack(alignment: .leading, spacing: 4) {
              Label("Update email and phone", systemImage: "checkmark.circle")
              Label("Change password", systemImage: "checkmark.circle")
              Label("Link/unlink OAuth identities", systemImage: "checkmark.circle")
              Label("Enable multi-factor authentication", systemImage: "checkmark.circle")
              Label("Enable biometric protection", systemImage: "checkmark.circle")
              Label("Reauthenticate for sensitive operations", systemImage: "checkmark.circle")
            }
            .font(.caption)
            .foregroundColor(.secondary)
          }
        }
      }
      .navigationTitle("Profile")
      .refreshable {
        await loadUser()
      }
    }
    .gitHubSourceLink()
    .task {
      await loadUser()
    }
    .sheet(isPresented: $showingMFA) {
      if let user {
        let hasMFA = !(user.factors ?? []).isEmpty
        let status: MFAStatus = hasMFA ? .verified : .unenrolled
        MFAFlow(status: status)
      }
    }
    #if canImport(LocalAuthentication)
      .sheet(isPresented: $showingBiometrics) {
        BiometricsConfigurationSheet()
      }
    #endif
  }

  @MainActor
  private func loadUser() async {
    do {
      error = nil
      isLoading = true
      defer { isLoading = false }

      user = try await supabase.auth.user()
    } catch {
      self.error = error
    }
  }

  @MainActor
  private func reauthenticate() async {
    do {
      error = nil
      isLoading = true
      defer { isLoading = false }

      try await supabase.auth.reauthenticate()

      // Refresh user data after reauthentication
      user = try await supabase.auth.user()
    } catch {
      self.error = error
    }
  }

  @MainActor
  private func unlinkIdentity(_ identity: UserIdentity) async {
    do {
      error = nil
      try await supabase.auth.unlinkIdentity(identity)

      // Refresh user data
      user = try await supabase.auth.user()
    } catch {
      self.error = error
    }
  }

  @MainActor
  private func signOut() async {
    do {
      try await supabase.auth.signOut()
    } catch {
      debug("Failed to sign out: \(error)")
    }
  }
}

#Preview {
  ProfileView()
}

// MARK: - Biometrics Views

#if canImport(LocalAuthentication)
  struct BiometricsRow: View {
    @Binding var showingBiometrics: Bool
    @Binding var error: Error?

    private var isBiometricsEnabled: Bool {
      supabase.auth.isBiometricsEnabled
    }

    private var biometryTypeName: String {
      let availability = supabase.auth.biometricsAvailability()
      switch availability.biometryType {
      case .none:
        return "None"
      case .touchID:
        return "Touch ID"
      case .faceID:
        return "Face ID"
      case .opticID:
        return "Optic ID"
      @unknown default:
        return "Biometrics"
      }
    }

    private var biometryIcon: String {
      let availability = supabase.auth.biometricsAvailability()
      switch availability.biometryType {
      case .faceID:
        return "faceid"
      case .touchID:
        return "touchid"
      case .opticID:
        return "opticid"
      default:
        return "lock.shield"
      }
    }

    var body: some View {
      HStack {
        Label(biometryTypeName, systemImage: biometryIcon)
        Spacer()
        if isBiometricsEnabled {
          Text("Enabled")
            .font(.caption)
            .foregroundColor(.green)
        } else {
          Text("Not Enabled")
            .font(.caption)
            .foregroundColor(.secondary)
        }
      }
      .contentShape(Rectangle())
      .onTapGesture {
        showingBiometrics = true
      }
    }
  }

  struct BiometricsConfigurationSheet: View {
    @Environment(\.dismiss) var dismiss

    @State private var selectedPolicy: BiometricPolicy = .default
    @State private var selectedEvaluationPolicy: BiometricEvaluationPolicy =
      .deviceOwnerAuthenticationWithBiometrics
    @State private var customTimeout: TimeInterval = 300
    @State private var isLoading = false
    @State private var error: Error?

    private var isBiometricsEnabled: Bool {
      supabase.auth.isBiometricsEnabled
    }

    private var availability: BiometricAvailability {
      supabase.auth.biometricsAvailability()
    }

    private var biometryTypeName: String {
      switch availability.biometryType {
      case .none:
        return "Biometrics"
      case .touchID:
        return "Touch ID"
      case .faceID:
        return "Face ID"
      case .opticID:
        return "Optic ID"
      @unknown default:
        return "Biometrics"
      }
    }

    var body: some View {
      NavigationStack {
        List {
          Section {
            Text(
              "Protect your session with \(biometryTypeName). When enabled, you'll need to authenticate before accessing your account."
            )
            .font(.caption)
            .foregroundColor(.secondary)
          }

          if !availability.isAvailable {
            Section {
              HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                  .foregroundColor(.orange)
                Text(
                  availability.error?.localizedDescription
                    ?? "Biometrics not available on this device"
                )
                .font(.caption)
              }
            }
          }

          Section("Status") {
            HStack {
              Text("Currently")
              Spacer()
              Text(isBiometricsEnabled ? "Enabled" : "Disabled")
                .foregroundColor(isBiometricsEnabled ? .green : .secondary)
            }
          }

          if !isBiometricsEnabled && availability.isAvailable {
            Section("Configuration") {
              Picker("Policy", selection: $selectedPolicy) {
                Text("Default (First Access)").tag(BiometricPolicy.default)
                Text("Always").tag(BiometricPolicy.always)
                Text("Session Timeout").tag(
                  BiometricPolicy.session(timeoutInSeconds: customTimeout))
                Text("App Lifecycle").tag(BiometricPolicy.appLifecycle)
              }

              if case .session = selectedPolicy {
                HStack {
                  Text("Timeout")
                  Spacer()
                  TextField("Seconds", value: $customTimeout, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                  Text("sec")
                    .foregroundColor(.secondary)
                }
              }

              Picker("Fallback", selection: $selectedEvaluationPolicy) {
                Text("Biometrics Only").tag(
                  BiometricEvaluationPolicy.deviceOwnerAuthenticationWithBiometrics)
                Text("Biometrics + Passcode").tag(
                  BiometricEvaluationPolicy.deviceOwnerAuthentication)
              }
            }

            Section {
              VStack(alignment: .leading, spacing: 4) {
                Text("Policy Options:")
                  .font(.caption)
                  .fontWeight(.medium)
                Group {
                  Text("Default: Authenticate once per app launch")
                  Text("Always: Authenticate every session access")
                  Text("Session Timeout: Authenticate after inactivity")
                  Text("App Lifecycle: Authenticate when returning from background")
                }
                .font(.caption2)
                .foregroundColor(.secondary)
              }
            }
          }

          if let error {
            Section {
              ErrorText(error)
            }
          }

          Section {
            if isBiometricsEnabled {
              Button(role: .destructive) {
                disableBiometrics()
              } label: {
                HStack {
                  Spacer()
                  if isLoading {
                    ProgressView()
                  } else {
                    Text("Disable \(biometryTypeName)")
                  }
                  Spacer()
                }
              }
            } else {
              Button {
                Task {
                  await enableBiometrics()
                }
              } label: {
                HStack {
                  Spacer()
                  if isLoading {
                    ProgressView()
                  } else {
                    Text("Enable \(biometryTypeName)")
                  }
                  Spacer()
                }
              }
              .disabled(!availability.isAvailable)
            }
          }
        }
        .navigationTitle(biometryTypeName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Done") {
              dismiss()
            }
          }
        }
      }
    }

    @MainActor
    private func enableBiometrics() async {
      do {
        error = nil
        isLoading = true
        defer { isLoading = false }

        let policy: BiometricPolicy
        if case .session = selectedPolicy {
          policy = .session(timeoutInSeconds: customTimeout)
        } else {
          policy = selectedPolicy
        }

        try await supabase.auth.enableBiometrics(
          title: "Enable \(biometryTypeName)",
          evaluationPolicy: selectedEvaluationPolicy,
          policy: policy
        )

        dismiss()
      } catch {
        self.error = error
      }
    }

    private func disableBiometrics() {
      error = nil
      supabase.auth.disableBiometrics()
      dismiss()
    }
  }
#endif
