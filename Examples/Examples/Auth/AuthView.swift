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
    case signInWithOAuth
    case signInWithOAuthUsingUIKit
    case googleSignInSDKFlow
    case signInAnonymously

    var title: String {
      switch self {
      case .emailAndPassword: "Auth with Email & Password"
      case .magicLink: "Auth with Magic Link"
      case .signInWithApple: "Sign in with Apple"
      case .signInWithOAuth: "Sign in with OAuth flow"
      case .signInWithOAuthUsingUIKit: "Sign in with OAuth flow (UIKit)"
      case .googleSignInSDKFlow: "Google Sign in (GIDSignIn SDK Flow)"
      case .signInAnonymously: "Sign in Anonymously"
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
    case .signInWithOAuth: SignInWithOAuth()
    case .signInWithOAuthUsingUIKit: UIViewControllerWrapper(SignInWithOAuthViewController())
      .edgesIgnoringSafeArea(.all)
    case .googleSignInSDKFlow: GoogleSignInSDKFlow()
    case .signInAnonymously: SignInAnonymously()
    }
  }
}

#Preview {
  AuthView()
}
