//
//  ExamplesApp.swift
//  Examples
//
//  Created by Guilherme Souza on 22/12/22.
//

import SwiftUI
import Supabase

@main
struct ExamplesApp: App {
  @State var supabaseInitialized = false
  
  var body: some Scene {
    WindowGroup {
      main
    }
  }

  @ViewBuilder
  var main: some View {
    if supabaseInitialized {
      RootView()
    } else {
      ProgressView()
        .task {
          await supabase.auth.initialize()
          supabaseInitialized = true
        }
    }
  }
}

let supabase = SupabaseClient(
  supabaseURL: Secrets.supabaseURL,
  supabaseKey: Secrets.supabaseAnonKey
)
