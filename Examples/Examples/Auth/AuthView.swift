//
//  AuthView.swift
//  Examples
//
//  Created by Guilherme Souza on 15/12/23.
//

import SwiftUI

struct AuthView: View {
  enum Option: CaseIterable {
    case emailAndPassword
    case magicLink
    case signInWithApple
    case googleSignInWebFlow
    case googleSignInSDKFlow

    var title: String {
      switch self {
      case .emailAndPassword: "Auth with Email & Password"
      case .magicLink: "Auth with Magic Link"
      case .signInWithApple: "Sign in with Apple"
      case .googleSignInWebFlow: "Google Sign in (Web Flow)"
      case .googleSignInSDKFlow: "Google Sign in (GIDSignIn SDK Flow)"
      }
    }
  }

  var body: some View {
    NavigationStack {
      List {
        ForEach(Option.allCases, id: \.self) { option in
          NavigationLink(option.title, value: option)
        }
      }
      .navigationDestination(for: Option.self) { options in
        options
          .navigationTitle(options.title)
      }
      .navigationBarTitleDisplayMode(.inline)
    }
  }
}

extension AuthView.Option: View {
  var body: some View {
    switch self {
    case .emailAndPassword: AuthWithEmailAndPassword()
    case .magicLink: AuthWithMagicLink()
    case .signInWithApple: SignInWithApple()
    case .googleSignInWebFlow: GoogleSignInWithWebFlow()
    case .googleSignInSDKFlow: GoogleSignInSDKFlow()
    }
  }
}

#Preview {
  AuthView()
}
