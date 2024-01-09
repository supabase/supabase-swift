//
//  ExamplesApp.swift
//  Examples
//
//  Created by Guilherme Souza on 22/12/22.
//

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
  options: .init(auth: .init(storage: KeychainLocalStorage(service: "supabase.gotrue.swift", accessGroup: nil)))
)
