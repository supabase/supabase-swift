//
//  SlackCloneApp.swift
//  SlackClone
//
//  Created by Guilherme Souza on 27/12/23.
//

import SwiftUI

@main
@MainActor
struct SlackCloneApp: App {
  let model = AppViewModel()

  var body: some Scene {
    WindowGroup {
      AppView(model: model)
        .onOpenURL { url in
          supabase.handle(url)
        }
    }
  }
}
