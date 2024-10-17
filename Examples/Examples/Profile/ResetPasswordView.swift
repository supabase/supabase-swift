//
//  ResetPasswordView.swift
//  Examples
//
//  Created by Guilherme Souza on 30/09/24.
//

import SwiftUI
import SwiftUINavigation

struct ResetPasswordView: View {
  @State private var email: String = ""
  @State private var showAlert = false
  @State private var alertMessage = ""

  var body: some View {
    VStack(spacing: 20) {
      Text("Reset Password")
        .font(.largeTitle)
        .fontWeight(.bold)

      TextField("Enter your email", text: $email)
        .textFieldStyle(RoundedBorderTextFieldStyle())
      #if !os(macOS)
        .autocapitalization(.none)
        .keyboardType(.emailAddress)
      #endif

      Button(action: resetPassword) {
        Text("Send Reset Link")
          .foregroundColor(.white)
          .padding()
          .background(Color.blue)
          .cornerRadius(10)
      }
    }
    .padding()
    .alert("Password reset", isPresented: $showAlert, actions: {}, message: {
      Text(alertMessage)
    })
  }

  func resetPassword() {
    Task {
      do {
        try await supabase.auth.resetPasswordForEmail(email)
        alertMessage = "Password reset email sent successfully"
      } catch {
        alertMessage = "Error sending password reset email: \(error.localizedDescription)"
      }
      showAlert = true
    }
  }
}
