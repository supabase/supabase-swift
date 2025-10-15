//
//  SignInAnonymously.swift
//  Examples
//
//  Demonstrates anonymous authentication for temporary guest access
//

import Supabase
import SwiftUI

struct SignInAnonymously: View {
  @State private var actionState: ActionState<Void, Error> = .idle

  var body: some View {
    List {
      Section {
        Text(
          "Create a temporary anonymous session without requiring any credentials. Perfect for guest access or trial periods."
        )
        .font(.caption)
        .foregroundColor(.secondary)
      }

      Section {
        Button("Sign In Anonymously") {
          Task {
            await signInAnonymously()
          }
        }
      }

      switch actionState {
      case .idle:
        EmptyView()
      case .inFlight:
        Section {
          ProgressView("Creating anonymous session...")
        }
      case .result(.success):
        Section {
          Text("Anonymous session created successfully!")
            .foregroundColor(.green)

          Text("You now have temporary access to the app.")
            .font(.caption)
            .foregroundColor(.secondary)
        }
      case .result(.failure(let error)):
        Section {
          ErrorText(error)
        }
      }

      Section("About") {
        VStack(alignment: .leading, spacing: 8) {
          Text("Anonymous Authentication")
            .font(.headline)

          Text(
            "Anonymous authentication allows users to access your app without providing any credentials. This creates a temporary session that can optionally be converted to a permanent account later."
          )
          .font(.caption)
          .foregroundColor(.secondary)

          Text("Use Cases:")
            .font(.subheadline)
            .padding(.top, 4)

          VStack(alignment: .leading, spacing: 4) {
            Label("Guest checkout in e-commerce apps", systemImage: "checkmark.circle")
            Label("Trial periods without signup", systemImage: "checkmark.circle")
            Label("Temporary data storage", systemImage: "checkmark.circle")
            Label("Frictionless onboarding", systemImage: "checkmark.circle")
          }
          .font(.caption)
          .foregroundColor(.secondary)

          Text("Features:")
            .font(.subheadline)
            .padding(.top, 8)

          VStack(alignment: .leading, spacing: 4) {
            Label("No email or password required", systemImage: "person.fill.questionmark")
            Label("Instant access", systemImage: "bolt.fill")
            Label("Can be converted to permanent account", systemImage: "arrow.right.circle.fill")
            Label("Full database access (with proper RLS)", systemImage: "lock.shield.fill")
          }
          .font(.caption)
          .foregroundColor(.secondary)

          Text("Important:")
            .font(.subheadline)
            .padding(.top, 8)

          Text(
            "Anonymous sessions are temporary. Users should convert their account to a permanent one (by adding email/password) if they want to preserve their data long-term."
          )
          .font(.caption)
          .foregroundColor(.orange)
          .padding(.vertical, 4)
          .padding(.horizontal, 8)
          .background(Color.orange.opacity(0.1))
          .cornerRadius(4)
        }
      }
    }
    .navigationTitle("Anonymous Sign In")
    .gitHubSourceLink()
  }

  private func signInAnonymously() async {
    actionState = .inFlight

    do {
      try await supabase.auth.signInAnonymously()
      actionState = .result(.success(()))
    } catch {
      actionState = .result(.failure(error))
    }
  }
}

#Preview {
  SignInAnonymously()
}
