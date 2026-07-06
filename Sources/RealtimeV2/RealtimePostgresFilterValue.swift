//
//  RealtimePostgresFilterValue.swift
//  Supabase
//
//  Created by Lucas Abijmil on 19/02/2025.
//

import Foundation

/// A value that can be used as a comparison operand in a ``RealtimePostgresFilter``.
///
/// The protocol requires conforming types to provide a ``rawValue`` string representation
/// that is embedded directly in the filter query sent to the Realtime server.
///
/// `String`, `Int`, `Double`, `Bool`, `UUID`, and `Date` all conform to this protocol out
/// of the box. Extend your own type if you need custom filter operands.
public protocol RealtimePostgresFilterValue {
  /// The string representation of this value as expected by the Realtime filter syntax.
  var rawValue: String { get }
}

extension String: RealtimePostgresFilterValue {
  /// The string itself.
  public var rawValue: String { self }
}

extension Int: RealtimePostgresFilterValue {
  /// The decimal string representation of this integer.
  public var rawValue: String { "\(self)" }
}

extension Double: RealtimePostgresFilterValue {
  /// The string representation of this floating-point value.
  public var rawValue: String { "\(self)" }
}

extension Bool: RealtimePostgresFilterValue {
  /// `"true"` or `"false"`.
  public var rawValue: String { "\(self)" }
}

extension UUID: RealtimePostgresFilterValue {
  /// The canonical uppercase UUID string (e.g. `"550E8400-E29B-41D4-A716-446655440000"`).
  public var rawValue: String { uuidString }
}

extension Date: RealtimePostgresFilterValue {
  /// An ISO 8601 string with fractional seconds and timezone offset
  /// (e.g. `"2024-01-15T12:00:00.000Z"`), suitable for comparison against `timestamptz` columns.
  public var rawValue: String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: self)
  }
}
