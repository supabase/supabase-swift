//
//  Supabase.swift
//  UserManagement
//
//  Created by Guilherme Souza on 17/11/23.
//

import Foundation
import OSLog
import Supabase

let supabase = SupabaseClient(
  supabaseURL: URL(string: "http://127.0.0.1:54321")!,
  supabaseKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU",
  options: .init(
    global: .init(logger: AppLogger())
  )
)

struct AppLogger: SupabaseLogger {
  let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "supabase")

  func log(message: SupabaseLogMessage) {
    switch message.level {
    case .verbose:
      logger.log(level: .info, "\(message.description)")
    case .debug:
      logger.log(level: .debug, "\(message.description)")
    case .warning, .error:
      logger.log(level: .error, "\(message.description)")
    }
  }
}
