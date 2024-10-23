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
        .onOpenURL {
          supabase.handle($0)
        }
    }
  }
}

let supabase = SupabaseClient(
  supabaseURL: URL(string: SupabaseConfig["SUPABASE_URL"]!)!,
  supabaseKey: SupabaseConfig["SUPABASE_ANON_KEY"]!,
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
