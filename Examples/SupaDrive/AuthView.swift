//
//  AuthView.swift
//  Examples
//
//  Created by Guilherme Souza on 02/07/24.
//

import Supabase
import SwiftUI

struct AuthView<Content: View>: View {
  @ViewBuilder var content: (Session) -> Content

  @State var session: Session?

  var body: some View {
    Group {
      if let session {
        content(session)
          .environment(\.supabaseSession, session)
      } else {
        LoginView()
      }
    }
    .task {
      for await (_, session) in supabase.auth.authStateChanges {
        self.session = session
      }
    }
  }

  struct LoginView: View {
    @State var email = ""
    @State var password = ""

    var body: some View {
      Form {
        Section {
          TextField("Email", text: $email)
          SecureField("Password", text: $password)
        }
        Section {
          Button("Sign in") {
            Task {
              do {
                try await supabase.auth.signIn(email: email, password: password)
              } catch {
                try await supabase.auth.signUp(email: email, password: password)
              }
            }
          }
        }
      }
    }
  }
}

enum SupabaseSesstionEnvironmentKey: EnvironmentKey {
  static var defaultValue: Session?
}

extension EnvironmentValues {
  var supabaseSession: Session? {
    get { self[SupabaseSesstionEnvironmentKey.self] }
    set { self[SupabaseSesstionEnvironmentKey.self] = newValue }
  }
}
