//
//  UserIdentityList.swift
//  Examples
//
//  Created by Guilherme Souza on 22/03/24.
//

import Supabase
import SwiftUI

struct UserIdentityList: View {
  @Environment(\.webAuthenticationSession) private var webAuthenticationSession

  @State private var identities = ActionState<[UserIdentity], any Error>.idle
  @State private var error: (any Error)?
  @State private var id = UUID()

  private var providers: [Provider] {
    let allProviders = Provider.allCases
    let identities = identities.success ?? []

    return allProviders.filter { provider in
      !identities.contains(where: { $0.provider == provider.rawValue })
    }
  }

  var body: some View {
    ActionStateView(state: $identities) {
      try await supabase.auth.userIdentities()
    } content: { identities in
      List {
        if let error {
          ErrorText(error)
        }

        ForEach(identities) { identity in
          Section {
            AnyJSONView(value: try! AnyJSON(identity))
          } footer: {
            Button("Unlink") {
              Task {
                do {
                  error = nil
                  try await supabase.auth.unlinkIdentity(identity)
                  id = UUID()
                } catch {
                  self.error = error
                }
              }
            }
          }
        }
      }
    }
    .id(id)
    #if swift(>=5.10)
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Menu("Add") {
            ForEach(providers) { provider in
              Button(provider.rawValue) {
                Task {
                  do {
                    if #available(iOS 17.4, *) {
                      let url = try await supabase.auth._getURLForLinkIdentity(provider: provider)
                      let accessToken = try await supabase.auth.session.accessToken

                      let callbackURL = try await webAuthenticationSession.authenticate(
                        using: url,
                        callback: .customScheme(Constants.redirectToURL.scheme!),
                        preferredBrowserSession: .shared,
                        additionalHeaderFields: ["Authorization": "Bearer \(accessToken)"]
                      )

                      debug("\(callbackURL)")
                    } else {
                      // Fallback on earlier versions
                    }

                  } catch {
                    self.error = error
                  }
                }
              }
            }
          }
        }
      }
    #endif
  }
}

#Preview {
  UserIdentityList()
}
