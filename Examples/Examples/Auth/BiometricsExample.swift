//
//  BiometricsExample.swift
//  Examples
//
//  Demonstrates biometric authentication for protecting session access
//

#if canImport(LocalAuthentication)
  import LocalAuthentication
  import Supabase
  import SwiftUI

  struct BiometricsExample: View {
    @Environment(AuthController.self) var auth

    @State private var availability: BiometricAvailability?
    @State private var selectedPolicy: BiometricPolicy = .default
    @State private var selectedEvaluationPolicy: BiometricEvaluationPolicy =
      .deviceOwnerAuthenticationWithBiometrics
    @State private var customTimeout: TimeInterval = 300
    @State private var error: Error?
    @State private var isLoading = false
    @State private var lastSessionAccess: Date?
    @State private var sessionInfo: String?

    private var isBiometricsEnabled: Bool {
      supabase.auth.isBiometricsEnabled
    }

    private var biometryTypeName: String {
      guard let availability else { return "Unknown" }
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
        return "Unknown"
      }
    }

    var body: some View {
      List {
        Section {
          Text(
            "Protect session access with Face ID, Touch ID, or Optic ID. When enabled, accessing the session requires biometric authentication."
          )
          .font(.caption)
          .foregroundColor(.secondary)
        }

        // Device Capabilities
        Section("Device Capabilities") {
          if let availability {
            HStack {
              Label("Biometry Type", systemImage: biometryIcon)
              Spacer()
              Text(biometryTypeName)
                .foregroundColor(.secondary)
            }

            HStack {
              Label("Available", systemImage: "checkmark.shield")
              Spacer()
              Image(
                systemName: availability.isAvailable
                  ? "checkmark.circle.fill" : "xmark.circle.fill"
              )
              .foregroundColor(availability.isAvailable ? .green : .red)
            }

            if let error = availability.error {
              HStack(alignment: .top) {
                Label("Error", systemImage: "exclamationmark.triangle")
                Spacer()
                Text(error.localizedDescription)
                  .font(.caption)
                  .foregroundColor(.red)
                  .multilineTextAlignment(.trailing)
              }
            }
          } else {
            HStack {
              ProgressView()
              Text("Checking availability...")
                .foregroundColor(.secondary)
            }
          }

          Button("Refresh Availability") {
            checkAvailability()
          }
        }

        // Current Status
        Section("Current Status") {
          HStack {
            Label("Biometrics Enabled", systemImage: "faceid")
            Spacer()
            Image(systemName: isBiometricsEnabled ? "checkmark.circle.fill" : "xmark.circle.fill")
              .foregroundColor(isBiometricsEnabled ? .green : .secondary)
          }

          HStack {
            Label("Auth Required", systemImage: "lock")
            Spacer()
            Image(
              systemName: supabase.auth.isBiometricAuthenticationRequired()
                ? "lock.fill" : "lock.open"
            )
            .foregroundColor(
              supabase.auth.isBiometricAuthenticationRequired() ? .orange : .secondary
            )
          }
        }

        // Configuration (only show when not enabled)
        if !isBiometricsEnabled {
          Section("Configuration") {
            Picker("Policy", selection: $selectedPolicy) {
              Text("Default (First Access)").tag(BiometricPolicy.default)
              Text("Always").tag(BiometricPolicy.always)
              Text("Session Timeout").tag(BiometricPolicy.session(timeoutInSeconds: customTimeout))
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

            Picker("Evaluation Policy", selection: $selectedEvaluationPolicy) {
              Text("Biometrics Only").tag(
                BiometricEvaluationPolicy.deviceOwnerAuthenticationWithBiometrics
              )
              Text("Biometrics + Passcode").tag(BiometricEvaluationPolicy.deviceOwnerAuthentication)
            }

            VStack(alignment: .leading, spacing: 8) {
              Text("Policy Descriptions:")
                .font(.caption)
                .foregroundColor(.secondary)

              Group {
                Text("Default: Auth on first access only")
                Text("Always: Auth every time session is accessed")
                Text("Session: Auth after timeout elapses")
                Text("App Lifecycle: Auth when returning from background")
              }
              .font(.caption2)
              .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
          }
        }

        // Actions
        Section("Actions") {
          if isBiometricsEnabled {
            Button(role: .destructive) {
              disableBiometrics()
            } label: {
              Label("Disable Biometrics", systemImage: "faceid")
            }

            Button {
              invalidateSession()
            } label: {
              Label("Invalidate Session", systemImage: "arrow.clockwise")
            }
          } else {
            Button {
              Task {
                await enableBiometrics()
              }
            } label: {
              Label("Enable Biometrics", systemImage: "faceid")
            }
            .disabled(availability?.isAvailable != true)
          }
        }

        // Test Session Access
        Section("Test Session Access") {
          Button {
            Task {
              await testSessionAccess()
            }
          } label: {
            Label("Access Session", systemImage: "key")
          }

          if let lastSessionAccess {
            HStack {
              Text("Last Access")
                .foregroundColor(.secondary)
              Spacer()
              Text(lastSessionAccess, style: .time)
                .font(.caption)
            }
          }

          if let sessionInfo {
            VStack(alignment: .leading, spacing: 4) {
              Text("Session Info:")
                .font(.caption)
                .foregroundColor(.secondary)
              Text(sessionInfo)
                .font(.caption2)
                .foregroundColor(.secondary)
            }
          }
        }

        // Error Display
        if let error {
          Section("Error") {
            ErrorText(error)
          }
        }

        // Loading Indicator
        if isLoading {
          Section {
            HStack {
              ProgressView()
              Text("Processing...")
                .foregroundColor(.secondary)
            }
          }
        }

        // About Section
        Section("About") {
          VStack(alignment: .leading, spacing: 8) {
            Text("Biometric Authentication")
              .font(.headline)

            Text(
              "Biometric authentication adds an extra layer of security by requiring Face ID, Touch ID, or Optic ID before accessing the user's session. This protects sensitive user data even if the device is unlocked."
            )
            .font(.caption)
            .foregroundColor(.secondary)

            Text("Features:")
              .font(.subheadline)
              .padding(.top, 4)

            VStack(alignment: .leading, spacing: 4) {
              Label("Configurable authentication policies", systemImage: "checkmark.circle")
              Label("Session timeout support", systemImage: "checkmark.circle")
              Label("App lifecycle integration", systemImage: "checkmark.circle")
              Label("Passcode fallback option", systemImage: "checkmark.circle")
            }
            .font(.caption)
            .foregroundColor(.secondary)

            Text("Note:")
              .font(.subheadline)
              .padding(.top, 4)

            Text(
              "Biometrics must be tested on a real device. Simulators do not support biometric authentication."
            )
            .font(.caption)
            .foregroundColor(.orange)
          }
        }
      }
      .navigationTitle("Biometrics")
      .gitHubSourceLink()
      .task {
        checkAvailability()
      }
      .animation(.default, value: isBiometricsEnabled)
    }

    private var biometryIcon: String {
      guard let availability else { return "questionmark.circle" }
      switch availability.biometryType {
      case .faceID:
        return "faceid"
      case .touchID:
        return "touchid"
      case .opticID:
        return "opticid"
      default:
        return "person.badge.shield.checkmark"
      }
    }

    private func checkAvailability() {
      availability = supabase.auth.biometricsAvailability()
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
          title: "Authenticate to enable biometrics",
          evaluationPolicy: selectedEvaluationPolicy,
          policy: policy
        )
      } catch {
        self.error = error
      }
    }

    private func disableBiometrics() {
      error = nil
      supabase.auth.disableBiometrics()
    }

    private func invalidateSession() {
      error = nil
      supabase.auth.invalidateBiometricSession()
    }

    @MainActor
    private func testSessionAccess() async {
      do {
        error = nil
        isLoading = true
        defer { isLoading = false }

        let session = try await supabase.auth.session
        lastSessionAccess = Date()

        let expiresAt = Date(timeIntervalSince1970: session.expiresAt)
        let expiresIn = expiresAt.timeIntervalSinceNow

        var info = "User: \(session.user.email ?? session.user.id.uuidString)"
        if expiresIn > 0 {
          let minutes = Int(expiresIn / 60)
          info += "\nExpires in: \(minutes) minutes"
        }
        sessionInfo = info
      } catch {
        self.error = error
        sessionInfo = nil
      }
    }
  }

  #Preview {
    NavigationStack {
      BiometricsExample()
        .environment(AuthController())
    }
  }
#endif
