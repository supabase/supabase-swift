//
//  ImportSessionView.swift
//  Examples
//
//  Demonstrates signing in with tokens that another system issued
//

import Supabase
import SwiftUI

struct ImportSessionView: View {
  @Environment(\.supabase) private var supabase

  @State private var accessToken = ""
  @State private var refreshToken = ""
  @State private var actionState = ActionState<Void, Error>.idle

  var body: some View {
    List {
      Section {
        Text(
          "Import a session from tokens that your server or another app issued. If the access token has expired, the SDK redeems the refresh token."
        )
        .font(.caption)
        .foregroundColor(.secondary)
      }

      Section("Tokens") {
        TextField("Access token", text: $accessToken)
          .autocorrectionDisabled()
          #if !os(macOS)
            .textInputAutocapitalization(.never)
          #endif

        TextField("Refresh token", text: $refreshToken)
          .autocorrectionDisabled()
          #if !os(macOS)
            .textInputAutocapitalization(.never)
          #endif

        Button("Import session") {
          Task { await importSession() }
        }
        .disabled(accessToken.isEmpty || refreshToken.isEmpty)
      }

      switch actionState {
      case .idle, .result(.success):
        EmptyView()
      case .inFlight:
        ProgressView()
      case .result(.failure(let error)):
        ErrorText(error)
      }

      Section("Code Example") {
        CodeExample(
          code: """
            let session = try await supabase.auth.importSession(
              accessToken: accessToken,
              refreshToken: refreshToken
            )
            """
        )
      }
    }
    .navigationTitle("Import Session")
    .gitHubSourceLink()
  }

  private func importSession() async {
    actionState = .inFlight
    do {
      try await supabase.auth.importSession(accessToken: accessToken, refreshToken: refreshToken)
      actionState = .result(.success(()))
    } catch {
      actionState = .result(.failure(error))
    }
  }
}

#Preview {
  NavigationStack {
    ImportSessionView()
  }
  .environment(\.supabase, supabaseClient)
}
