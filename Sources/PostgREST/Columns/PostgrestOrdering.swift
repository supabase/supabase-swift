//
//  PostgrestOrdering.swift
//  PostgREST
//
//  Created by Guilherme Souza on 26/08/26.
//

/// One sort key: a column expression, optionally with a direction and a null placement.
///
/// ```swift
/// .order { $0.priority.desc() }
/// .order { $0.id }              // breaks ties in the first, ascending by default
/// ```
///
/// Omitting the direction sends `order=id` bare, so PostgREST's own default applies rather than
/// a value frozen into the client.
public struct PostgrestOrdering<Root: PostgrestRelation>: Sendable {
  let column: String

  /// `nil` sends no direction, so PostgREST's default applies (ascending, `NULL`s last on 16.1).
  let ascending: Bool?

  /// `nil` sends no placement, so the database default applies.
  ///
  /// Deliberately unlike `PostgrestTransformBuilder.order(_:ascending:nullsFirst:)`, which always
  /// appends one — see [SDK-1633](https://linear.app/supabase/issue/SDK-1633).
  var nullPlacement: PostgrestNullPlacement?

  var rendered: String {
    column
      + (ascending.map { ".\($0 ? "asc" : "desc")" } ?? "")
      + (nullPlacement.map { ".\($0.rawValue)" } ?? "")
  }

  /// Sorts `NULL`s before non-null values.
  public func nullsFirst() -> Self {
    var copy = self
    copy.nullPlacement = .first
    return copy
  }

  /// Sorts `NULL`s after non-null values.
  public func nullsLast() -> Self {
    var copy = self
    copy.nullPlacement = .last
    return copy
  }
}

/// Where `NULL`s sort relative to other values.
public struct PostgrestNullPlacement: RawRepresentable, Hashable, Sendable {
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// `nullsfirst`
  public static let first = PostgrestNullPlacement(rawValue: "nullsfirst")

  /// `nullslast`
  public static let last = PostgrestNullPlacement(rawValue: "nullslast")
}

extension PostgrestOrderableExpression {
  /// Sorts by this expression, smallest first.
  ///
  /// Null placement is left to the database unless you chain
  /// ``PostgrestOrdering/nullsFirst()`` or ``PostgrestOrdering/nullsLast()``.
  public func asc() -> PostgrestOrdering<Root> {
    PostgrestOrdering(column: postgrestExpression, ascending: true)
  }

  /// Sorts by this expression, largest first.
  public func desc() -> PostgrestOrdering<Root> {
    PostgrestOrdering(column: postgrestExpression, ascending: false)
  }
}
