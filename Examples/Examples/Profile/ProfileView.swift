//
//  ProfileView.swift
//  Examples
//
//  Created by Guilherme Souza on 21/03/24.
//

import Supabase
import SwiftUI

struct ProfileView: View {
  @State var user: User?

  var identities: [UserIdentity] {
    user?.identities ?? []
  }

  var body: some View {
    NavigationStack {
      List {
        if let user,
           let json = try? AnyJSON(user) {
          Section {
            AnyJSONView(value: json)
          }
        }

        if let user {
          NavigationLink("Update profile") {
            UpdateProfileView(user: user)
              .navigationTitle("Update profile")
          }
        }

        NavigationLink("Identities") {
          UserIdentityList()
            .navigationTitle("Identities")
        }

        Button("Reauthenticate") {
          Task {
            try! await supabase.auth.reauthenticate()
          }
        }

        Menu("Unlink identity") {
          ForEach(identities) { identity in
            Button(identity.provider) {
              Task {
                do {
                  try await supabase.auth.unlinkIdentity(identity)
                } catch {
                  debug("Fail to unlink identity: \(error)")
                }
              }
            }
          }
        }

        Button("Sign out", role: .destructive) {
          Task {
            try! await supabase.auth.signOut()
          }
        }
      }
      .navigationTitle("Profile")
    }
    .task {
      do {
        user = try await supabase.auth.user()
      } catch {
        debug("Fail to fetch user: \(error)")
      }
    }
  }
}

#Preview {
  ProfileView()
}
