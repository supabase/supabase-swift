//
//  BiometricKeychainExample.swift
//  Examples
//
//  Demonstrates biometric-protected keychain storage for session data
//

#if canImport(LocalAuthentication)
  import Auth
  import LocalAuthentication
  import Supabase
  import SwiftUI

  struct BiometricKeychainExample: View {
    @State private var availability:
      (isAvailable: Bool, biometryType: LABiometryType, error: Error?)?
    @State private var selectedAccessControl: BiometricAccessControl = .biometryOrPasscode
    @State private var promptMessage = "Authenticate to access your session"
    @State private var testResult: String?
    @State private var error: Error?
    @State private var isLoading = false

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
        return "lock.shield"
      }
    }

    var body: some View {
      List {
        Section {
          Text(
            "BiometricKeychainLocalStorage integrates biometric authentication directly into the keychain. The OS automatically prompts for biometrics when accessing stored data."
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

          Button("Refresh") {
            checkAvailability()
          }
        }

        // Configuration
        Section("Configuration") {
          Picker("Access Control", selection: $selectedAccessControl) {
            Text("Biometry Only").tag(BiometricAccessControl.biometryOnly)
            Text("Biometry + Passcode").tag(BiometricAccessControl.biometryOrPasscode)
            Text("User Presence").tag(BiometricAccessControl.userPresence)
          }

          VStack(alignment: .leading, spacing: 4) {
            Text("Prompt Message")
              .font(.caption)
              .foregroundColor(.secondary)
            TextField("Message", text: $promptMessage)
              .textFieldStyle(.roundedBorder)
          }
        }

        // Code Example
        Section("Usage Example") {
          VStack(alignment: .leading, spacing: 8) {
            Text("Configure at client initialization:")
              .font(.caption)
              .foregroundColor(.secondary)

            Text(codeExample)
              .font(.system(.caption2, design: .monospaced))
              .padding(8)
              .background(Color(.systemGray6))
              .cornerRadius(8)
          }
        }

        // Test Section
        Section("Test Storage") {
          Button {
            Task {
              await testBiometricStorage()
            }
          } label: {
            Label("Test Biometric Storage", systemImage: "play.fill")
          }
          .disabled(availability?.isAvailable != true)

          if isLoading {
            HStack {
              ProgressView()
              Text("Testing...")
                .foregroundColor(.secondary)
            }
          }

          if let testResult {
            Text(testResult)
              .font(.caption)
              .foregroundColor(.green)
          }
        }

        if let error {
          Section("Error") {
            ErrorText(error)
          }
        }

        // About Section
        Section("About") {
          VStack(alignment: .leading, spacing: 8) {
            Text("Keychain-Level Biometrics")
              .font(.headline)

            Text(
              "This approach integrates biometric protection at the storage layer using keychain access control. When you store data, it's protected with biometric requirements. The OS automatically handles the biometric prompt when accessing the data."
            )
            .font(.caption)
            .foregroundColor(.secondary)

            Text("Access Control Levels:")
              .font(.subheadline)
              .padding(.top, 4)

            VStack(alignment: .leading, spacing: 4) {
              Label("Biometry Only: Face ID / Touch ID required", systemImage: "faceid")
              Label("Biometry + Passcode: Biometrics with passcode fallback", systemImage: "lock")
              Label("User Presence: Any authentication method", systemImage: "person.fill")
            }
            .font(.caption)
            .foregroundColor(.secondary)

            Text("Benefits:")
              .font(.subheadline)
              .padding(.top, 4)

            VStack(alignment: .leading, spacing: 4) {
              Label("OS handles biometric UI automatically", systemImage: "checkmark.circle")
              Label("Protection at the storage level", systemImage: "checkmark.circle")
              Label("No additional state management needed", systemImage: "checkmark.circle")
              Label("Simpler implementation", systemImage: "checkmark.circle")
            }
            .font(.caption)
            .foregroundColor(.secondary)

            Text("Note:")
              .font(.subheadline)
              .padding(.top, 4)

            Text(
              "Biometrics must be tested on a real device. The biometric prompt appears automatically when accessing stored data."
            )
            .font(.caption)
            .foregroundColor(.orange)
          }
        }
      }
      .navigationTitle("Biometric Keychain")
      .gitHubSourceLink()
      .task {
        checkAvailability()
      }
    }

    private var codeExample: String {
      """
      let storage = BiometricKeychainLocalStorage(
        accessControl: .\(accessControlName),
        promptMessage: "\(promptMessage)"
      )

      let client = SupabaseClient(
        supabaseURL: url,
        supabaseKey: key,
        options: .init(
          auth: .init(localStorage: storage)
        )
      )
      """
    }

    private var accessControlName: String {
      switch selectedAccessControl {
      case .biometryOnly:
        return "biometryOnly"
      case .biometryOrPasscode:
        return "biometryOrPasscode"
      case .userPresence:
        return "userPresence"
      }
    }

    private func checkAvailability() {
      availability = BiometricKeychainLocalStorage.checkBiometricAvailability()
    }

    @MainActor
    private func testBiometricStorage() async {
      error = nil
      testResult = nil
      isLoading = true
      defer { isLoading = false }

      do {
        // Create a biometric-protected storage
        let storage = BiometricKeychainLocalStorage(
          service: "supabase.example.biometric-test",
          accessControl: selectedAccessControl,
          promptMessage: promptMessage
        )

        // Test data
        let testKey = "test-biometric-key"
        let testData = "Hello, Biometrics!".data(using: .utf8)!

        // Store (this sets up biometric protection)
        try storage.store(key: testKey, value: testData)

        // Retrieve (this triggers biometric prompt on real device)
        if let retrieved = try storage.retrieve(key: testKey),
          let string = String(data: retrieved, encoding: .utf8)
        {
          testResult = "Success! Retrieved: \"\(string)\""
        }

        // Clean up
        try storage.remove(key: testKey)

      } catch let keychainError as BiometricKeychainError {
        switch keychainError {
        case .userCanceled:
          error = keychainError
          testResult = nil
        case .authenticationFailed:
          error = keychainError
        default:
          error = keychainError
        }
      } catch {
        self.error = error
      }
    }
  }

  #Preview {
    NavigationStack {
      BiometricKeychainExample()
    }
  }
#endif
