//
//  RealtimePostgresFilterValue.swift
//  Supabase
//
//  Created by Lucas Abijmil on 19/02/2025.
//

import Foundation

/// A value that can be used to filter Realtime changes in a channel.
public protocol RealtimePostgresFilterValue {
  var rawValue: String { get }
}

extension String: RealtimePostgresFilterValue {
  public var rawValue: String { self }
}

extension Int: RealtimePostgresFilterValue {
  public var rawValue: String { "\(self)" }
}

extension Double: RealtimePostgresFilterValue {
  public var rawValue: String { "\(self)" }
}

extension Bool: RealtimePostgresFilterValue {
  public var rawValue: String { "\(self)" }
}

extension UUID: RealtimePostgresFilterValue {
  public var rawValue: String { uuidString }
}

extension Date: RealtimePostgresFilterValue {
  public var rawValue: String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: self)
  }
}
