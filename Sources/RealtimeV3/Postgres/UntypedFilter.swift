//
//  UntypedFilter.swift
//  RealtimeV3
//
//  Created by Guilherme Souza on 29/06/26.
//

import Foundation

// MARK: - UntypedFilter

/// An untyped filter for Realtime postgres-changes subscriptions.
///
/// Use this when the row type cannot or does not conform to `RealtimeTable`.
/// Column names are raw strings; values are still constrained to
/// `RealtimePostgresFilterValue` for correct wire encoding.
///
/// Each clause serializes to `column=op.value`. Compound filters join multiple
/// clauses with `,` (AND semantics on the backend). Use `.not` to negate a
/// filter: it prepends `not.` before the operator in every clause it wraps, so
/// `.not(.eq("col", 1))` produces `col=not.eq.1`.
///
/// `isNull` produces `column=is.null`; `isNotNull` produces
/// `column=not.is.null` (matching the backend `not.` prefix convention).
///
/// The `in` factory enforces a maximum of 100 values — the backend hard-limits
/// this, and exceeding it is a programmer error, so it traps via `precondition`.
///
/// String values that contain commas (`,`), opening parentheses (`(`),
/// closing parentheses (`)`), or backslashes (`\`) are automatically
/// double-quoted inside an `in` value list, with internal double-quotes escaped
/// as `\"` and backslashes escaped as `\\`.
public struct UntypedFilter: Sendable {

  // MARK: - Stored properties

  /// The wire-format representation of this filter.
  ///
  /// A single clause has the form `column=op.value`. A compound filter joins
  /// multiple clauses with `,`.
  public let serialized: String

  // MARK: - Initializer

  private init(_ serialized: String) {
    self.serialized = serialized
  }

  // MARK: - Comparison factories

  /// Creates an equality filter: `column=eq.value`.
  public static func eq(
    _ column: String,
    _ value: any RealtimePostgresFilterValue
  ) -> UntypedFilter {
    UntypedFilter("\(column)=eq.\(value.rawValue)")
  }

  /// Creates an inequality filter: `column=neq.value`.
  public static func neq(
    _ column: String,
    _ value: any RealtimePostgresFilterValue
  ) -> UntypedFilter {
    UntypedFilter("\(column)=neq.\(value.rawValue)")
  }

  /// Creates a greater-than filter: `column=gt.value`.
  public static func gt(
    _ column: String,
    _ value: any RealtimePostgresFilterValue
  ) -> UntypedFilter {
    UntypedFilter("\(column)=gt.\(value.rawValue)")
  }

  /// Creates a greater-than-or-equal filter: `column=gte.value`.
  public static func gte(
    _ column: String,
    _ value: any RealtimePostgresFilterValue
  ) -> UntypedFilter {
    UntypedFilter("\(column)=gte.\(value.rawValue)")
  }

  /// Creates a less-than filter: `column=lt.value`.
  public static func lt(
    _ column: String,
    _ value: any RealtimePostgresFilterValue
  ) -> UntypedFilter {
    UntypedFilter("\(column)=lt.\(value.rawValue)")
  }

  /// Creates a less-than-or-equal filter: `column=lte.value`.
  public static func lte(
    _ column: String,
    _ value: any RealtimePostgresFilterValue
  ) -> UntypedFilter {
    UntypedFilter("\(column)=lte.\(value.rawValue)")
  }

  // MARK: - Set membership

  /// Creates an `in` filter: `column=in.(v1,v2,...)`.
  ///
  /// - Precondition: `values.count <= 100`. The backend hard-limits in-lists to
  ///   100 entries; exceeding this is a programmer error.
  ///
  /// String values that contain commas, parentheses, or backslashes are
  /// double-quoted with internal escaping so the backend can parse them correctly.
  public static func `in`(
    _ column: String,
    _ values: [any RealtimePostgresFilterValue]
  ) -> UntypedFilter {
    precondition(
      values.count <= 100,
      "UntypedFilter.in: too many values (\(values.count)); the backend permits at most 100"
    )
    let encoded =
      values
      .map { quoteInValue($0.rawValue) }
      .joined(separator: ",")
    return UntypedFilter("\(column)=in.(\(encoded))")
  }

  // MARK: - Pattern matching

  /// Creates a LIKE filter: `column=like.pattern`.
  public static func like(_ column: String, _ pattern: String) -> UntypedFilter {
    UntypedFilter("\(column)=like.\(pattern)")
  }

  /// Creates an ILIKE (case-insensitive LIKE) filter: `column=ilike.pattern`.
  public static func ilike(_ column: String, _ pattern: String) -> UntypedFilter {
    UntypedFilter("\(column)=ilike.\(pattern)")
  }

  /// Creates a regular-expression match filter: `column=match.pattern`.
  public static func match(_ column: String, _ pattern: String) -> UntypedFilter {
    UntypedFilter("\(column)=match.\(pattern)")
  }

  /// Creates a case-insensitive regular-expression match filter:
  /// `column=imatch.pattern`.
  public static func imatch(_ column: String, _ pattern: String) -> UntypedFilter {
    UntypedFilter("\(column)=imatch.\(pattern)")
  }

  // MARK: - Null checks

  /// Creates an IS NULL filter: `column=is.null`.
  public static func isNull(_ column: String) -> UntypedFilter {
    UntypedFilter("\(column)=is.null")
  }

  /// Creates an IS NOT NULL filter: `column=not.is.null`.
  ///
  /// Uses the `not.` prefix convention (consistent with all other negations) rather
  /// than the separate `isnotnull` operator.
  public static func isNotNull(_ column: String) -> UntypedFilter {
    UntypedFilter("\(column)=not.is.null")
  }

  // MARK: - Distinct check

  /// Creates an IS DISTINCT FROM filter: `column=isdistinct.value`.
  public static func isDistinct(
    _ column: String,
    _ value: any RealtimePostgresFilterValue
  ) -> UntypedFilter {
    UntypedFilter("\(column)=isdistinct.\(value.rawValue)")
  }

  // MARK: - Composition

  /// Returns a new filter that ANDs this filter with `other` by joining their
  /// serialized clauses with `,`.
  public func and(_ other: UntypedFilter) -> UntypedFilter {
    UntypedFilter("\(serialized),\(other.serialized)")
  }

  /// Returns a new filter that ANDs all given filters by joining their serialized
  /// clauses with `,`.
  public static func all(_ filters: [UntypedFilter]) -> UntypedFilter {
    UntypedFilter(filters.map(\.serialized).joined(separator: ","))
  }

  /// Returns a new filter that negates every clause in `filter` by inserting
  /// `not.` before the operator token.
  ///
  /// The transformation is applied to each comma-separated clause independently,
  /// so `not(.eq("a",1).and(.eq("b",2)))` produces `a=not.eq.1,b=not.eq.2`.
  public static func not(_ filter: UntypedFilter) -> UntypedFilter {
    let negated = filter.serialized
      .split(separator: ",", omittingEmptySubsequences: false)
      .map { clause -> String in
        let s = String(clause)
        // Each clause has the form `column=op.rest` (or `column=not.op.rest`).
        // Find the `=` and insert `not.` immediately after it.
        guard let eqRange = s.range(of: "=") else {
          return s
        }
        let afterEq = s[eqRange.upperBound...]
        return "\(s[..<eqRange.upperBound])not.\(afterEq)"
      }
      .joined(separator: ",")
    return UntypedFilter(negated)
  }

  // MARK: - Private helpers

  /// Quotes a raw value string for use inside an `in(...)` value list.
  ///
  /// A value is double-quoted when it contains `,`, `(`, `)`, `\`, or `"`.
  /// Inside the quotes, `"` is escaped as `\"` and `\` as `\\`.
  private static func quoteInValue(_ raw: String) -> String {
    let needsQuoting =
      raw.contains(",")
      || raw.contains("(")
      || raw.contains(")")
      || raw.contains("\\")
      || raw.contains("\"")
    guard needsQuoting else { return raw }
    let escaped =
      raw
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
    return "\"\(escaped)\""
  }
}
