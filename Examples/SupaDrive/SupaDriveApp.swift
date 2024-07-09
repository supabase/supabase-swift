//
//  SupaDriveApp.swift
//  SupaDrive
//
//  Created by Guilherme Souza on 02/07/24.
//

import Supabase
import SwiftUI

let supabase = SupabaseClient(
  supabaseURL: URL(string: "http://127.0.0.1:54321")!,
  supabaseKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0",
  options: SupabaseClientOptions(global: .init(logger: AppLogger()))
)

struct AppLogger: SupabaseLogger {
  func log(message: SupabaseLogMessage) {
    print(message.description)
  }
}

@main
struct SupaDriveApp: App {
  var body: some Scene {
    WindowGroup {
      AuthView { session in
        AppView(path: [session.user.id.uuidString.lowercased()])
      }
    }
  }
}
