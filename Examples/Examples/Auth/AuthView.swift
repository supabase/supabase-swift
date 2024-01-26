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
    case googleSignIn

    var title: String {
      switch self {
      case .emailAndPassword: "Auth with Email & Password"
      case .magicLink: "Auth with Magic Link"
      case .signInWithApple: "Sign in with Apple"
      case .googleSignIn: "Google Sign in"
      }
    }
  }

  var body: some View {
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

extension AuthView.Option: View {
  var body: some View {
    switch self {
    case .emailAndPassword: AuthWithEmailAndPassword()
    case .magicLink: AuthWithMagicLink()
    case .signInWithApple: SignInWithApple()
    case .googleSignIn: GoogleSignIn()
    }
  }
}

#Preview {
  AuthView()
}
