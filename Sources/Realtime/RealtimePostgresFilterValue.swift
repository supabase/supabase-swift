//
//  RealtimePostgresFilterValue.swift
//  Supabase
//
//  Created by Lucas Abijmil on 19/02/2025.
//

public import Foundation

/// A value that can be used as a comparison operand in a ``RealtimePostgresFilter``.
///
/// `String`, `Int`, `Double`, `Bool`, `UUID`, and `Date` conform out of the box. Conform your own
/// type by returning its filter text from ``realtimeFilterValue``.
public protocol RealtimePostgresFilterValue: Sendable {
  /// The value as it appears in the filter, before the SDK quotes and escapes it.
  var realtimeFilterValue: String { get }
}

extension String: RealtimePostgresFilterValue {
  /// The string itself.
  public var realtimeFilterValue: String { self }
}

extension Int: RealtimePostgresFilterValue {
  /// The decimal representation.
  public var realtimeFilterValue: String { "\(self)" }
}

extension Double: RealtimePostgresFilterValue {
  /// The decimal representation.
  public var realtimeFilterValue: String { "\(self)" }
}

extension Bool: RealtimePostgresFilterValue {
  /// `"true"` or `"false"`.
  public var realtimeFilterValue: String { "\(self)" }
}

extension UUID: RealtimePostgresFilterValue {
  /// The canonical uppercase UUID string.
  public var realtimeFilterValue: String { uuidString }
}

extension Date: RealtimePostgresFilterValue {
  /// An ISO 8601 string with fractional seconds, such as `"2024-01-15T12:00:00.000Z"`, for
  /// comparing against `timestamptz` columns.
  public var realtimeFilterValue: String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: self)
  }
}
