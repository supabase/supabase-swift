//
//  RealtimeFilterValue.swift
//  Supabase
//
//  Created by Lucas Abijmil on 19/02/2025.
//

import Foundation

/// A value that can be used to filter Realtime changes in a channel.
public protocol RealtimeFilterValue {
  var rawValue: String { get }
}

extension String: RealtimeFilterValue {
  public var rawValue: String { self }
}

extension Int: RealtimeFilterValue {
  public var rawValue: String { "\(self)" }
}

extension Double: RealtimeFilterValue {
  public var rawValue: String { "\(self)" }
}

extension Bool: RealtimeFilterValue {
  public var rawValue: String { "\(self)" }
}

extension UUID: RealtimeFilterValue {
  public var rawValue: String { uuidString }
}

extension Date: RealtimeFilterValue {
  public var rawValue: String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: self)
  }
}

extension Array: RealtimeFilterValue where Element: RealtimeFilterValue {
  public var rawValue: String {
    map(\.rawValue).joined(separator: ",")
  }
}
