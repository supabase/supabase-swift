//
//  UpdateProfileView.swift
//  Examples
//
//  Demonstrates updating user email, phone, and password
//

import Supabase
import SwiftUI

struct UpdateProfileView: View {
  let user: User

  @State var email = ""
  @State var phone = ""
  @State var password = ""

  @State var otp = ""
  @State var showTokenField = false

  @State var actionState: ActionState<Void, Error> = .idle
  @State var verifyActionState: ActionState<Void, Error> = .idle
  @State var successMessage: String?

  var formUpdated: Bool {
    emailChanged || phoneChanged || !password.isEmpty
  }

  var emailChanged: Bool {
    email != user.email && !email.isEmpty
  }

  var phoneChanged: Bool {
    phone != user.phone && !phone.isEmpty
  }

  var body: some View {
    List {
      Section {
        Text("Update your account credentials. Changes to email or phone require verification.")
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

        if emailChanged {
          Text("A confirmation email will be sent to verify this change")
            .font(.caption)
            .foregroundColor(.orange)
        }
      }

      Section("Phone Number") {
        TextField("Phone", text: $phone)
          .textContentType(.telephoneNumber)
          .autocorrectionDisabled()
          #if !os(macOS)
            .keyboardType(.phonePad)
            .textInputAutocapitalization(.never)
          #endif

        if phoneChanged {
          Text("You'll need to verify this phone number with an OTP code")
            .font(.caption)
            .foregroundColor(.orange)
        }
      }

      Section("New Password") {
        SecureField("New password (leave blank to keep current)", text: $password)
          .textContentType(.newPassword)

        if !password.isEmpty {
          Text("Password will be updated immediately")
            .font(.caption)
            .foregroundColor(.green)
        }
      }

      Section {
        Button("Update Profile") {
          Task {
            await updateButtonTapped()
          }
        }
        .disabled(!formUpdated)
      }

      switch actionState {
      case .idle:
        EmptyView()
      case .inFlight:
        Section {
          ProgressView("Updating profile...")
        }
      case .result(.success):
        if let successMessage {
          Section("Success") {
            Text(successMessage)
              .foregroundColor(.green)
          }
        }
      case .result(.failure(let error)):
        Section {
          ErrorText(error)
        }
      }

      if showTokenField {
        Section("Phone Verification") {
          Text("Enter the OTP code sent to your new phone number")
            .font(.caption)
            .foregroundColor(.secondary)

          TextField("6-digit code", text: $otp)
            .textContentType(.oneTimeCode)
            .autocorrectionDisabled()
            #if !os(macOS)
              .keyboardType(.numberPad)
              .textInputAutocapitalization(.never)
            #endif

          Button("Verify Phone") {
            Task {
              await verifyTapped()
            }
          }
          .disabled(otp.isEmpty)
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
            Text("Phone number verified successfully!")
              .foregroundColor(.green)
          }
        case .result(.failure(let error)):
          Section {
            ErrorText(error)
          }
        }
      }

      Section("About") {
        VStack(alignment: .leading, spacing: 8) {
          Text("Profile Updates")
            .font(.headline)

          Text(
            "You can update your email, phone number, and password. Email and phone changes require verification for security."
          )
          .font(.caption)
          .foregroundColor(.secondary)

          Text("Verification Requirements:")
            .font(.subheadline)
            .padding(.top, 4)

          VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
              Image(systemName: "envelope.fill")
                .foregroundColor(.accentColor)
              VStack(alignment: .leading, spacing: 2) {
                Text("Email Changes")
                  .font(.caption)
                  .fontWeight(.medium)
                Text("Confirmation link sent to new email address")
                  .font(.caption)
                  .foregroundColor(.secondary)
              }
            }

            HStack(alignment: .top, spacing: 8) {
              Image(systemName: "phone.fill")
                .foregroundColor(.accentColor)
              VStack(alignment: .leading, spacing: 2) {
                Text("Phone Changes")
                  .font(.caption)
                  .fontWeight(.medium)
                Text("6-digit OTP code sent via SMS")
                  .font(.caption)
                  .foregroundColor(.secondary)
              }
            }
            .padding(.top, 4)

            HStack(alignment: .top, spacing: 8) {
              Image(systemName: "key.fill")
                .foregroundColor(.accentColor)
              VStack(alignment: .leading, spacing: 2) {
                Text("Password Changes")
                  .font(.caption)
                  .fontWeight(.medium)
                Text("Applied immediately, no verification needed")
                  .font(.caption)
                  .foregroundColor(.secondary)
              }
            }
            .padding(.top, 4)
          }
        }
      }
    }
    .navigationTitle("Update Profile")
    .gitHubSourceLink()
    .onAppear {
      email = user.email ?? ""
      phone = user.phone ?? ""
    }
  }

  @MainActor
  private func updateButtonTapped() async {
    var attributes = UserAttributes()

    if emailChanged {
      attributes.email = email
    }

    if phoneChanged {
      attributes.phone = phone
    }

    if password.isEmpty == false {
      attributes.password = password
    }

    actionState = .inFlight

    do {
      try await supabase.auth.update(user: attributes, redirectTo: Constants.redirectToURL)

      var messages: [String] = []
      if emailChanged {
        messages.append("Email update sent - check your inbox")
      }
      if phoneChanged {
        messages.append("Phone update initiated - enter OTP below")
        showTokenField = true
      }
      if !password.isEmpty {
        messages.append("Password updated successfully")
      }

      successMessage = messages.joined(separator: "\n")
      actionState = .result(.success(()))

      // Clear password field after successful update
      password = ""
    } catch {
      actionState = .result(.failure(error))
    }
  }

  @MainActor
  private func verifyTapped() async {
    verifyActionState = .inFlight

    do {
      try await supabase.auth.verifyOTP(phone: phone, token: otp, type: .phoneChange)
      verifyActionState = .result(.success(()))

      showTokenField = false
      otp = ""
    } catch {
      verifyActionState = .result(.failure(error))
    }
  }
}

#Preview {
  UpdateProfileView(
    user: User(
      id: UUID(),
      appMetadata: [:],
      userMetadata: [:],
      aud: "",
      createdAt: Date(),
      updatedAt: Date()
    )
  )
}
