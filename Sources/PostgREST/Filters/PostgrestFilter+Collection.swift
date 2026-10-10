//
//  PostgrestFilter+Collection.swift
//  PostgREST
//
//  Created by Guilherme Souza on 26/08/26.
//

// MARK: - Array operands
//
// `cs`, `cd` and `ov` each get three methods, because the operand literal is chosen by the
// column's Postgres type rather than by the operator: `{a,b}` for an array, `[1,3)` for a range,
// `{"a":1}` for jsonb. Mixing them is a 400.
//
// Every shape is type-checked: `where Value == [E]`, `where Value == _PostgresRange<B>` and
// `where Value == JSONValue`. So `contains(["a"])` on a `String` column does not compile, nor does
// a `daterange` operand on an `int4range` column, nor `containsJSON` on a `text` column. Each
// would be a server error (`42883 operator does not exist`).
//
// The array operand is the `[E]` itself: its `rawValue` is the `{a,b}` literal with every member
// escaped as the literal requires.

extension _PostgrestFilterableExpression {
  /// Matches rows where this array column contains every element of `values`.
  ///
  /// An empty `values` matches every row whose column is non-null — the opposite of `in` and
  /// `likeAnyOf`, since every array contains the empty array.
  public func contains<E: PostgrestArrayElement>(_ values: [E]) -> _PostgrestFilter<Root>
  where Value == [E] {
    _PostgrestFilter(column: postgrestExpression, operator: .contains, value: values)
  }

  /// Matches rows where every element of this array column is contained by `values`.
  public func containedBy<E: PostgrestArrayElement>(_ values: [E]) -> _PostgrestFilter<Root>
  where Value == [E] {
    _PostgrestFilter(column: postgrestExpression, operator: .containedBy, value: values)
  }

  /// Matches rows where this array column shares at least one element with `values`.
  public func overlaps<E: PostgrestArrayElement>(_ values: [E]) -> _PostgrestFilter<Root>
  where Value == [E] {
    _PostgrestFilter(column: postgrestExpression, operator: .overlaps, value: values)
  }
}

// MARK: - Range operands
//
// A range operand is a single value, so a group quotes it: a bare `)`/`]` closes an enclosing
// `or=(…)` early and 400s. At top level it stays bare, since `eq."[1,10)"` is a `22P02`. Every
// operator takes a range, never an element: `int_span=cs.5` is a `22P02` too.

extension _PostgrestFilterableExpression {
  /// Matches rows where this range column contains `range`.
  ///
  /// - Parameter range: A range of the column's own type, for example `"[2,3)"`.
  public func containsRange<B>(_ range: _PostgresRange<B>) -> _PostgrestFilter<Root>
  where Value == _PostgresRange<B> {
    _PostgrestFilter(column: postgrestExpression, operator: .contains, value: range)
  }

  /// Matches rows where this range column is contained by `range`.
  public func containedByRange<B>(_ range: _PostgresRange<B>) -> _PostgrestFilter<Root>
  where Value == _PostgresRange<B> {
    _PostgrestFilter(column: postgrestExpression, operator: .containedBy, value: range)
  }

  /// Matches rows where this range column overlaps `range`.
  public func overlapsRange<B>(_ range: _PostgresRange<B>) -> _PostgrestFilter<Root>
  where Value == _PostgresRange<B> {
    _PostgrestFilter(column: postgrestExpression, operator: .overlaps, value: range)
  }

  /// Matches rows where this range column is strictly to the left of `range`.
  ///
  /// - Parameter range: A range of the column's own type, for example `"[2024-01-01,2024-02-01)"`.
  public func rangeLt<B>(_ range: _PostgresRange<B>) -> _PostgrestFilter<Root>
  where Value == _PostgresRange<B> {
    _PostgrestFilter(column: postgrestExpression, operator: .rangeLt, value: range)
  }

  /// Matches rows where this range column is strictly to the right of `range`.
  public func rangeGt<B>(_ range: _PostgresRange<B>) -> _PostgrestFilter<Root>
  where Value == _PostgresRange<B> {
    _PostgrestFilter(column: postgrestExpression, operator: .rangeGt, value: range)
  }

  /// Matches rows where this range column does not extend to the left of `range`.
  public func rangeGte<B>(_ range: _PostgresRange<B>) -> _PostgrestFilter<Root>
  where Value == _PostgresRange<B> {
    _PostgrestFilter(column: postgrestExpression, operator: .rangeGte, value: range)
  }

  /// Matches rows where this range column does not extend to the right of `range`.
  public func rangeLte<B>(_ range: _PostgresRange<B>) -> _PostgrestFilter<Root>
  where Value == _PostgresRange<B> {
    _PostgrestFilter(column: postgrestExpression, operator: .rangeLte, value: range)
  }

  /// Matches rows where this range column is adjacent to `range`.
  public func rangeAdjacent<B>(_ range: _PostgresRange<B>) -> _PostgrestFilter<Root>
  where Value == _PostgresRange<B> {
    _PostgrestFilter(column: postgrestExpression, operator: .rangeAdjacent, value: range)
  }
}

// MARK: - JSON operands

extension _PostgrestFilterableExpression where Value == JSONValue {
  /// Matches rows where this `jsonb` column contains `json`.
  ///
  /// ```swift
  /// .where { $0.data.containsJSON(["a": 1]) }   // data=cs.{"a":1}
  /// ```
  ///
  /// - Parameter json: Any JSON value. An object matches rows holding at least those keys and
  ///   values; on an array column, `[20]` or `20` matches arrays holding `20`.
  public func containsJSON(_ json: JSONValue) -> _PostgrestFilter<Root> {
    _PostgrestFilter(column: postgrestExpression, operator: .contains, value: json)
  }

  /// Matches rows where this `jsonb` column is contained by `json`.
  public func containedByJSON(_ json: JSONValue) -> _PostgrestFilter<Root> {
    _PostgrestFilter(column: postgrestExpression, operator: .containedBy, value: json)
  }
}

// MARK: - Text search

extension _PostgrestFilterableExpression where Value == String {
  /// Matches rows where this `text` or `tsvector` column matches the full-text `query`.
  ///
  /// - Parameters:
  ///   - query: The search query.
  ///   - config: The text-search configuration, for example `"english"`. Defaults to `nil`,
  ///     which leaves the database default in place.
  ///   - type: How to turn `query` into a `tsquery`. Defaults to `nil`, meaning `to_tsquery`.
  public func textSearch(
    _ query: String,
    config: String? = nil,
    type: TextSearchType? = nil
  ) -> _PostgrestFilter<Root> {
    _PostgrestFilter(
      column: postgrestExpression,
      operator: .textSearch(config: config, type: type),
      value: query
    )
  }
}
