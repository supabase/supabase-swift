//
//  AuthView.swift
//  Examples
//
//  Created by Guilherme Souza on 02/07/24.
//

import SwiftUI

struct AuthView: View {
  @State var userId: String?

  var body: some View {
    Group {
      if let userId {
        AppView(path: [userId.lowercased()])
      } else {
        ProgressView()
          .task {
            do {
              userId = try? await supabase.auth.session.user.id.uuidString
              if userId == nil {
                userId = try await supabase.auth.signIn(email: "admin@supabase.io", password: "The.pass@00!").user.id.uuidString
              }
            } catch {
              dump(error)
            }
          }
      }
    }
  }
}
