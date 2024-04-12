//
//  ExamplesApp.swift
//  Examples
//
//  Created by Guilherme Souza on 22/12/22.
//

import GoogleSignIn
import Supabase
import SwiftUI

@main
struct ExamplesApp: App {
  var body: some Scene {
    WindowGroup {
      RootView()
        .environment(AuthController())
    }
  }
}

let supabase = SupabaseClient(
  supabaseURL: Secrets.supabaseURL,
  supabaseKey: Secrets.supabaseAnonKey,
  options: .init(
    auth: .init(redirectToURL: Constants.redirectToURL),
    global: .init(
      logger: ConsoleLogger()
    )
  )
)

struct ConsoleLogger: SupabaseLogger {
  func log(message: SupabaseLogMessage) {
    print(message)
  }
}
