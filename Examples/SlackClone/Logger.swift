//
//  Logger.swift
//  SlackClone
//
//  Created by Guilherme Souza on 23/01/24.
//

import Foundation
import OSLog

extension Logger {
  static let main = Self(subsystem: "com.supabase.slack-clone", category: "app")
}
