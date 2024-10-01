//
//  AuthController.swift
//  Examples
//
//  Created by Guilherme Souza on 22/12/22.
//

import Auth
import SwiftUI

@Observable
@MainActor
final class AuthController {
  var session: Session?
  var isPasswordRecoveryFlow: Bool = false

  var currentUserID: UUID {
    guard let id = session?.user.id else {
      preconditionFailure("Required session.")
    }

    return id
  }

  @ObservationIgnored
  private var observeAuthStateChangesTask: Task<Void, Never>?

  init() {
    observeAuthStateChangesTask = Task {
      for await (event, session) in supabase.auth.authStateChanges {
        if [.initialSession, .signedIn, .signedOut].contains(event) {
          self.session = session
        }

        if event == .passwordRecovery {
          self.isPasswordRecoveryFlow = true
        }
      }
    }
  }

  deinit {
    observeAuthStateChangesTask?.cancel()
  }
}
