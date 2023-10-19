//
//  Logger.swift
//  ProductSample
//
//  Created by Guilherme Souza on 19/10/23.
//

import Foundation
import OSLog

extension Logger {
  static func make(category: String) -> Logger {
    Logger(subsystem: Bundle.main.bundleIdentifier ?? "", category: category)
  }
}
