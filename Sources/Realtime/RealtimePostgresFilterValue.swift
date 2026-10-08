//
//  RealtimePostgresFilterValue.swift
//  Supabase
//
//  Created by Lucas Abijmil on 19/02/2025.
//

public import Foundation

/// A value that can be used as a comparison operand in a ``RealtimePostgresFilter``.
///
/// `String`, `Int`, `Double`, `Bool`, `UUID`, and `Date` conform out of the box. A `Date` is sent
/// as an ISO 8601 string with fractional seconds, a `UUID` as its canonical string. Any other
/// conforming type is sent as its `rawValue` when it is `RawRepresentable`, and as
/// `String(describing:)` otherwise.
public protocol RealtimePostgresFilterValue: Sendable {}

extension String: RealtimePostgresFilterValue {}
extension Int: RealtimePostgresFilterValue {}
extension Double: RealtimePostgresFilterValue {}
extension Bool: RealtimePostgresFilterValue {}
extension UUID: RealtimePostgresFilterValue {}
extension Date: RealtimePostgresFilterValue {}

extension RealtimePostgresFilter {
  /// The text of `value` as it appears in a filter, before escaping.
  package static func format(_ value: any RealtimePostgresFilterValue) -> String {
    switch value {
    case let string as String:
      return string
    case let uuid as UUID:
      return uuid.uuidString
    case let date as Date:
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      return formatter.string(from: date)
    case let rawRepresentable as any RawRepresentable:
      return "\(rawRepresentable.rawValue)"
    default:
      return "\(value)"
    }
  }
}
