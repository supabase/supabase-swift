//
//  AuthView.swift
//  ProductSample
//
//  Created by Guilherme Souza on 19/10/23.
//

import SwiftUI

struct AuthView: View {
  @ObservedObject var model: AuthViewModel

  var body: some View {
    Form {
      Section {
        TextField("Email", text: $model.email)
          .keyboardType(.emailAddress)
          .textContentType(.emailAddress)
          .autocorrectionDisabled()
          .textInputAutocapitalization(.never)
        SecureField("Password", text: $model.password)
          .textContentType(.password)
          .autocorrectionDisabled()
          .textInputAutocapitalization(.never)
      }

      Section {
        Button("Sign in") {
          Task {
            await model.signInButtonTapped()
          }
        }
        Button("Sign up") {
          Task {
            await model.signUpButtonTapped()
          }
        }
        Button("Sign in with Apple") {
          Task {
            await model.signInWithAppleButtonTapped()
          }
        }
      }

      if let status = model.status {
        switch status {
        case let .error(error):
          Text(error.localizedDescription).font(.callout).foregroundStyle(.red)
        case .requiresConfirmation:
          Text(
            "Account created, but it requires confirmation, click the verification link sent to the registered email."
          )
          .font(.callout)
        case .loading:
          ProgressView()
        }
      }
    }
    .onOpenURL { url in
      Task { await model.onOpenURL(url) }
    }
  }
}
