//
//  SupabaseLogLevel.swift
//
//
//  Created by Guilherme Souza on 15/01/24.
//

import Foundation

public enum SupabaseLogLevel: Int, Codable, CustomStringConvertible, Sendable {
  case debug
  case warning
  case error

  public var description: String {
    switch self {
    case .debug:
      "debug"
    case .warning:
      "warning"
    case .error:
      "error"
    }
  }
}
