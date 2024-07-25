//
//  SupaDriveApp.swift
//  SupaDrive
//
//  Created by Guilherme Souza on 02/07/24.
//

import Supabase
import SwiftUI
import OSLog

let supabase = SupabaseClient(
  supabaseURL: URL(string: "http://127.0.0.1:54321")!,
  supabaseKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0",
  options: SupabaseClientOptions(global: .init(logger: Logger.supabase))
)

extension Logger: @retroactive SupabaseLogger {
  static let supabase = Logger(subsystem: "supadrive", category: "supabase")

  public func log(message: SupabaseLogMessage) {
    let logType: OSLogType = switch message.level {
    case .debug: .debug
    case .error: .error
    case .verbose: .info
    case .warning: .fault
    }

    self.log(level: logType, "\(message)")
  }
}

@main
struct SupaDriveApp: App {
  var body: some Scene {
    WindowGroup {
      AuthView { session in
        AppView(
          model: AppModel(root: PanelModel(path: session.user.id.uuidString.lowercased()))
        )
      }
    }
  }
}
