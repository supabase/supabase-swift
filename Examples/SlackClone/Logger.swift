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
  static let main = Self(subsystem: "com.supabase.SlackClone", category: "app")
}

final class SupabaseLoggerImpl: SupabaseLogger, @unchecked Sendable {
  private let lock = NSLock()
  private var loggers: [String: Logger] = [:]

  func log(message: SupabaseLogMessage) {
    lock.withLock {
      if loggers[message.system] == nil {
        loggers[message.system] = Logger(
          subsystem: "com.supabase.SlackClone.supabase-swift",
          category: message.system
        )
      }

      let logger = loggers[message.system]!

      switch message.level {
      case .debug: logger.debug("\(message)")
      case .error: logger.error("\(message)")
      case .verbose: logger.info("\(message)")
      case .warning: logger.notice("\(message)")
      }
    }
  }
}
