//
//  SlackCloneApp.swift
//  SlackClone
//
//  Created by Guilherme Souza on 27/12/23.
//

import OSLog
import Supabase
import SwiftUI

@main
@MainActor
struct SlackCloneApp: App {
  let model = AppViewModel()

  var body: some Scene {
    WindowGroup {
      AppView(model: model)
        .onOpenURL { url in
          Task {
            do {
              try await supabase.handleRedirect(url)
            } catch {
              Logger.main.debug("Failed to handle a redirect: \(error)")
            }
          }
        }
    }
  }
}
