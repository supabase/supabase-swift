//
//  UpdatePasswordView.swift
//  Examples
//
//  Shown after a password recovery link signs the user in
//

import Supabase
import SwiftUI

struct UpdatePasswordView: View {
  @Environment(\.supabase) private var supabase
  @Environment(\.dismiss) private var dismiss

  @State private var password = ""
  @State private var actionState = ActionState<Void, Error>.idle

  var body: some View {
    Form {
      Section("New password") {
        SecureField("Password", text: $password)
          .textContentType(.newPassword)

        Button("Update password") {
          Task { await updatePassword() }
        }
        .disabled(password.isEmpty)
      }

      switch actionState {
      case .idle, .result(.success):
        EmptyView()
      case .inFlight:
        ProgressView()
      case .result(.failure(let error)):
        ErrorText(error)
      }
    }
    .gitHubSourceLink()
  }

  private func updatePassword() async {
    actionState = .inFlight
    do {
      try await supabase.auth.updateUser(UserAttributes(password: password))
      dismiss()
    } catch {
      actionState = .result(.failure(error))
    }
  }
}

#Preview {
  UpdatePasswordView()
}
