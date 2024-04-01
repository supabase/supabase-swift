//
//  SignInAnonymously.swift
//  Examples
//
//  Created by Guilherme Souza on 01/04/24.
//

import Supabase
import SwiftUI

struct SignInAnonymously: View {
  var body: some View {
    Button("Sign in") {
      Task {
        do {
          try await supabase.auth.signInAnonymously()
        } catch {
          debug("Error signin in anonymously: \(error)")
        }
      }
    }
  }
}

#Preview {
  SignInAnonymously()
}
