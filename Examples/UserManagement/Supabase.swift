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
  supabaseURL: URL(string: "https://PROJECT_ID.supabase.co")!,
  supabaseKey: "YOUR_SUPABASE_ANON_KEY",
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
