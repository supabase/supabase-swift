//
//  SignInWithPhone.swift
//  Examples
//
//  Demonstrates phone number authentication with OTP verification
//

import SwiftUI

struct SignInWithPhone: View {
  @Environment(\.openURL) private var openURL
  @State var phone = ""
  @State var code = ""

  @State var actionState: ActionState<Void, Error> = .idle
  @State var verifyActionState: ActionState<Void, Error> = .idle

  @State var isVerifyStep = false

  var body: some View {
    List {
      if isVerifyStep {
        verifySection
      } else {
        phoneSection
      }

      Section("About") {
        VStack(alignment: .leading, spacing: 8) {
          Text("Phone Authentication")
            .font(.headline)

          Text(
            "Phone authentication allows users to sign in using their phone number. A one-time code (OTP) is sent via SMS to verify the phone number."
          )
          .font(.caption)
          .foregroundColor(.secondary)

          Text("Process:")
            .font(.subheadline)
            .padding(.top, 4)

          VStack(alignment: .leading, spacing: 4) {
            Text("1. Enter phone number with country code")
            Text("2. Receive OTP code via SMS")
            Text("3. Enter the verification code")
            Text("4. Access granted upon successful verification")
          }
          .font(.caption)
          .foregroundColor(.secondary)

          Text("Features:")
            .font(.subheadline)
            .padding(.top, 8)

          VStack(alignment: .leading, spacing: 4) {
            Label("Fast and convenient", systemImage: "checkmark.circle")
            Label("No email required", systemImage: "checkmark.circle")
            Label("SMS delivery", systemImage: "checkmark.circle")
            Label("Time-limited codes", systemImage: "checkmark.circle")
          }
          .font(.caption)
          .foregroundColor(.secondary)
        }
      }
    }
    .navigationTitle("Phone OTP")
    .gitHubSourceLink()
  }

  var phoneSection: some View {
    Group {
      Section {
        Text("Enter your phone number to receive a verification code via SMS")
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Section("Phone Number") {
        TextField("Phone (e.g., +1234567890)", text: $phone)
          .textContentType(.telephoneNumber)
          .autocorrectionDisabled()
          #if !os(macOS)
            .keyboardType(.phonePad)
            .textInputAutocapitalization(.never)
          #endif

        Text("Include country code (e.g., +1 for US)")
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Section {
        Button("Send Verification Code") {
          Task {
            await sendCodeToNumberTapped()
          }
        }
        .disabled(phone.isEmpty)
      }

      switch actionState {
      case .idle:
        EmptyView()
      case .inFlight:
        Section {
          ProgressView("Sending code...")
        }
      case .result(.success):
        EmptyView()
      case .result(.failure(let error)):
        Section {
          ErrorText(error)
        }
      }
    }
  }

  var verifySection: some View {
    Group {
      Section {
        Text("Enter the verification code sent to \(phone)")
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Section("Verification Code") {
        TextField("6-digit code", text: $code)
          .textContentType(.oneTimeCode)
          .autocorrectionDisabled()
          #if !os(macOS)
            .keyboardType(.numberPad)
            .textInputAutocapitalization(.never)
          #endif
      }

      Section {
        Button("Verify Code") {
          Task {
            await verifyButtonTapped()
          }
        }
        .disabled(code.isEmpty)

        Button("Change Phone Number") {
          isVerifyStep = false
          code = ""
          verifyActionState = .idle
        }
      }

      switch verifyActionState {
      case .idle:
        EmptyView()
      case .inFlight:
        Section {
          ProgressView("Verifying code...")
        }
      case .result(.success):
        Section {
          Text("Code verified successfully!")
            .foregroundColor(.green)
        }
      case .result(.failure(let error)):
        Section {
          ErrorText(error)
        }
      }
    }
  }

  private func sendCodeToNumberTapped() async {
    actionState = .inFlight

    do {
      try await supabase.auth.signInWithOTP(phone: phone)
      actionState = .result(.success(()))
      isVerifyStep = true
    } catch {
      actionState = .result(.failure(error))
    }
  }

  private func verifyButtonTapped() async {
    verifyActionState = .inFlight
    do {
      try await supabase.auth.verifyOTP(phone: phone, token: code, type: .sms)
      verifyActionState = .result(.success(()))
    } catch {
      verifyActionState = .result(.failure(error))
    }
  }
}

#Preview {
  SignInWithPhone()
}
