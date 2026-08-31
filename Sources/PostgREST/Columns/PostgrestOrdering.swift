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

  /// Places `NULL`s relative to non-null values.
  ///
  /// ```swift
  /// .order { $0.priority.desc().nulls(.first) }
  /// ```
  public func nulls(_ placement: PostgrestNullPlacement) -> Self {
    var copy = self
    copy.nullPlacement = placement
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
  /// Null placement is left to the database unless you chain ``PostgrestOrdering/nulls(_:)``.
  public func asc() -> PostgrestOrdering<Root> {
    PostgrestOrdering(column: postgrestExpression, ascending: true)
  }

  /// Sorts by this expression, largest first.
  public func desc() -> PostgrestOrdering<Root> {
    PostgrestOrdering(column: postgrestExpression, ascending: false)
  }

  /// Sorts by this expression with an explicit `NULL` placement, leaving the direction to
  /// PostgREST.
  ///
  /// ```swift
  /// .order { $0.dueDate.nulls(.first) }   // order=due_at.nullsfirst
  /// ```
  ///
  /// The two parts are independent on the wire, so a placement does not require picking a
  /// direction: `order=name.nullsfirst` is a 200. Without this, wanting PostgREST's default
  /// direction *and* an explicit placement would force a direction into the query anyway.
  public func nulls(_ placement: PostgrestNullPlacement) -> PostgrestOrdering<Root> {
    PostgrestOrdering(column: postgrestExpression, ascending: nil, nullPlacement: placement)
  }
}
