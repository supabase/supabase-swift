//
//  AuthExamplesView.swift
//  Examples
//
//  Demonstrates all authentication methods available in Supabase Auth
//

import SwiftUI

struct AuthExamplesView: View {
  var body: some View {
    List {
      Section {
        Text("Explore authentication methods and user management with Supabase Auth")
          .font(.subheadline)
          .foregroundColor(.secondary)
      }

      Section("Email Authentication") {
        NavigationLink(destination: AuthWithEmailAndPassword()) {
          ExampleRow(
            title: "Email & Password",
            description: "Sign up and sign in with email and password",
            icon: "envelope.fill"
          )
        }

        NavigationLink(destination: AuthWithMagicLink()) {
          ExampleRow(
            title: "Magic Link",
            description: "Passwordless authentication via email",
            icon: "link.circle.fill"
          )
        }
      }

      Section("Phone Authentication") {
        NavigationLink(destination: SignInWithPhone()) {
          ExampleRow(
            title: "Phone OTP",
            description: "Sign in with phone number and verification code",
            icon: "phone.fill"
          )
        }
      }

      Section("Social Authentication") {
        NavigationLink(destination: SignInWithApple()) {
          ExampleRow(
            title: "Sign in with Apple",
            description: "Apple ID authentication",
            icon: "apple.logo"
          )
        }

        NavigationLink(destination: SignInWithFacebook()) {
          ExampleRow(
            title: "Sign in with Facebook",
            description: "Facebook social authentication",
            icon: "f.circle.fill"
          )
        }

        NavigationLink(destination: SignInWithOAuth()) {
          ExampleRow(
            title: "OAuth Providers",
            description: "Generic OAuth flow for various providers",
            icon: "person.crop.circle.badge.checkmark"
          )
        }

        #if canImport(UIKit)
          NavigationLink(
            destination: UIViewControllerWrapper(SignInWithOAuthViewController())
              .edgesIgnoringSafeArea(.all)
          ) {
            ExampleRow(
              title: "OAuth with UIKit",
              description: "OAuth authentication using UIKit",
              icon: "rectangle.portrait.and.arrow.right"
            )
          }
        #endif

        NavigationLink(destination: GoogleSignInSDKFlow()) {
          ExampleRow(
            title: "Google Sign-In SDK",
            description: "Google authentication using official SDK",
            icon: "g.circle.fill"
          )
        }
      }

      Section("Guest Access") {
        NavigationLink(destination: SignInAnonymously()) {
          ExampleRow(
            title: "Anonymous Sign In",
            description: "Create temporary anonymous sessions",
            icon: "person.fill.questionmark"
          )
        }
      }

      #if canImport(LocalAuthentication)
        Section("Security") {
          NavigationLink(destination: BiometricsExample()) {
            ExampleRow(
              title: "Biometrics",
              description: "Protect session access with Face ID / Touch ID",
              icon: "faceid"
            )
          }
        }
      #endif
    }
    .navigationTitle("Authentication")
  }
}

#Preview {
  NavigationStack {
    AuthExamplesView()
  }
}
