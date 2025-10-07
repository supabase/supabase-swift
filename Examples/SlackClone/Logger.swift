//
//  Logger.swift
//  SlackClone
//
//  Created by Guilherme Souza on 23/01/24.
//

import Foundation
import OSLog
import Supabase

extension Logger {
  static let main = Self(subsystem: "com.supabase.slack-clone", category: "app")
  static let supabase = Self(subsystem: "com.supabase.slack-clone", category: "supabase")
}

struct SupaLogger: SupabaseLogger {
  func log(message: SupabaseLogMessage) {
    Task {
      let logger = await Logger.supabase

      switch message.level {
      case .debug: logger.debug("\(message, privacy: .public)")
      case .error: logger.error("\(message, privacy: .public)")
      case .verbose: logger.info("\(message, privacy: .public)")
      case .warning: logger.notice("\(message, privacy: .public)")
      }
    }
  }
}
