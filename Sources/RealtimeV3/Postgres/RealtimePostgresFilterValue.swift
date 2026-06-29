//
//  RealtimePostgresFilterValue.swift
//  RealtimeV3
//
//  Created by Guilherme Souza on 29/06/26.
//

import Foundation

/// A value that can be used to filter Realtime postgres-changes in a channel.
///
/// Conforming types must provide a `rawValue` string that represents the value
/// in the wire format expected by the Realtime backend (i.e. the portion after
/// the operator dot in `column=op.value`).
public protocol RealtimePostgresFilterValue: Sendable {
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
