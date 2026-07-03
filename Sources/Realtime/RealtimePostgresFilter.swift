//
//  RealtimePostgresFilter.swift
//  Supabase
//
//  Created by Lucas Abijmil on 19/02/2025.
//

import Foundation
import Helpers
import IssueReporting

/// Value accepted by the ``RealtimePostgresFilter/is(_:value:)`` operator.
///
/// Mirrors the SQL `IS` check: `column IS null / true / false / unknown`.
public enum RealtimePostgresIsValue: Sendable {
  case null
  case `true`
  case `false`
  case unknown

  var rawValue: String {
    switch self {
    case .null: return "null"
    case .true: return "true"
    case .false: return "false"
    case .unknown: return "unknown"
    }
  }
}

/// A filter that can be used in Realtime `postgres_changes` subscriptions.
///
/// A filter is a `column=operator.value` expression evaluated server-side (for
/// example `id=eq.1` or `title=like.%foo%`). Operators mirror the PostgREST
/// surface that Realtime supports.
///
/// Use ``not(_:)`` to negate a single condition (`column=not.operator.value`)
/// and ``and(_:)`` to combine multiple conditions with a logical `AND`
/// (comma-separated).
///
/// ```swift
/// // amount=gt.100,status=not.in.(draft),title=like.%foo%
/// let filter: RealtimePostgresFilter = .and([
///   .gt("amount", value: 100),
///   .not(.in("status", values: ["draft"])),
///   .like("title", value: "%foo%"),
/// ])
/// ```
///
/// Values containing reserved characters (`,`, `(`, `)`, `"`, `\`) — or
/// surrounding whitespace — are automatically double-quoted and escaped the way
/// PostgREST does, so they survive the server's filter parser.
public enum RealtimePostgresFilter {
  /// Match rows where `column` equals `value` (`column=eq.value`).
  case eq(_ column: String, value: any RealtimePostgresFilterValue)
  /// Match rows where `column` does not equal `value` (`column=neq.value`).
  case neq(_ column: String, value: any RealtimePostgresFilterValue)
  /// Match rows where `column` is greater than `value` (`column=gt.value`).
  case gt(_ column: String, value: any RealtimePostgresFilterValue)
  /// Match rows where `column` is greater than or equal to `value` (`column=gte.value`).
  case gte(_ column: String, value: any RealtimePostgresFilterValue)
  /// Match rows where `column` is less than `value` (`column=lt.value`).
  case lt(_ column: String, value: any RealtimePostgresFilterValue)
  /// Match rows where `column` is less than or equal to `value` (`column=lte.value`).
  case lte(_ column: String, value: any RealtimePostgresFilterValue)
  /// Match rows where `column` is one of `values` (`column=in.(a,b,c)`). Duplicates are removed.
  case `in`(_ column: String, values: [any RealtimePostgresFilterValue])
  /// Match rows where `column` matches the case-sensitive `value` pattern (`column=like.value`).
  case like(_ column: String, value: any RealtimePostgresFilterValue)
  /// Match rows where `column` matches the case-insensitive `value` pattern (`column=ilike.value`).
  case ilike(_ column: String, value: any RealtimePostgresFilterValue)
  /// Match rows where `column` matches the POSIX regex `value` (`column=match.value`).
  case match(_ column: String, value: any RealtimePostgresFilterValue)
  /// Match rows where `column` matches the case-insensitive POSIX regex `value` (`column=imatch.value`).
  case imatch(_ column: String, value: any RealtimePostgresFilterValue)
  /// Match rows where `column` `IS` the given value (`column=is.null`).
  case `is`(_ column: String, value: RealtimePostgresIsValue)
  /// Match rows where `column` is distinct from `value` (`column=isdistinct.value`). NULL-safe inequality.
  case isDistinct(_ column: String, value: any RealtimePostgresFilterValue)
  /// Negate any single-condition filter with the `not.` prefix (`column=not.operator.value`).
  indirect case not(RealtimePostgresFilter)
  /// Combine multiple conditions with a logical `AND` (comma-separated).
  case and([RealtimePostgresFilter])

  private var parts: (column: String, expr: String)? {
    switch self {
    case .eq(let column, let value):
      return (column, "eq.\(Self.serialize(value))")
    case .neq(let column, let value):
      return (column, "neq.\(Self.serialize(value))")
    case .gt(let column, let value):
      return (column, "gt.\(Self.serialize(value))")
    case .gte(let column, let value):
      return (column, "gte.\(Self.serialize(value))")
    case .lt(let column, let value):
      return (column, "lt.\(Self.serialize(value))")
    case .lte(let column, let value):
      return (column, "lte.\(Self.serialize(value))")
    case .in(let column, let values):
      let items = Self.dedupe(values)
        .map { Self.serialize($0) }
        .joined(separator: ",")
      return (column, "in.(\(items))")
    case .like(let column, let value):
      return (column, "like.\(Self.serialize(value))")
    case .ilike(let column, let value):
      return (column, "ilike.\(Self.serialize(value))")
    case .match(let column, let value):
      return (column, "match.\(Self.serialize(value))")
    case .imatch(let column, let value):
      return (column, "imatch.\(Self.serialize(value))")
    case .is(let column, let value):
      return (column, "is.\(value.rawValue)")
    case .isDistinct(let column, let value):
      return (column, "isdistinct.\(Self.serialize(value))")
    case .not, .and:
      return nil
    }
  }

  var value: String {
    switch self {
    case .and(let filters):
      return filters.map(\.value).joined(separator: ",")
    case .not(let inner):
      guard let parts = inner.parts else {
        reportIssue(
          "RealtimePostgresFilter.not can only negate a single condition, not `.not`/`.and`."
        )
        return inner.value
      }
      return "\(parts.column)=not.\(parts.expr)"
    default:
      let parts = parts!
      return "\(parts.column)=\(parts.expr)"
    }
  }

  private static func serialize(_ value: any RealtimePostgresFilterValue) -> String {
    escapePostgRESTFilterValue(value.rawValue)
  }

  private static func dedupe(_ values: [any RealtimePostgresFilterValue])
    -> [any RealtimePostgresFilterValue]
  {
    var seen = Set<String>()
    return values.filter { seen.insert($0.rawValue).inserted }
  }
}
