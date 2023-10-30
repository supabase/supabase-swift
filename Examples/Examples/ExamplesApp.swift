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
  @StateObject var auth = AuthController()

  var body: some Scene {
    WindowGroup {
      RootView()
        .environmentObject(auth)
    }
  }
}

let supabase = SupabaseClient(
  supabaseURL: Secrets.supabaseURL,
  supabaseKey: Secrets.supabaseAnonKey
)
