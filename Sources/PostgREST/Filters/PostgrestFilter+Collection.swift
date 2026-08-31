//
//  PostgrestFilter+Collection.swift
//  PostgREST
//
//  Created by Guilherme Souza on 26/08/26.
//

/// `{a,b}` — the Postgres array literal the array and multi-pattern operators take.
///
/// Members go through the array escaper: a raw join splits any element containing a comma into
/// two, and a stray `{`/`}` corrupts the literal's delimiters.
func postgrestArray(_ values: [some PostgrestArrayElement]) -> String {
  "{\(values.map(\.postgrestArrayElement).joined(separator: ","))}"
}

// MARK: - Array operands
//
// `cs`, `cd` and `ov` each get three methods, because the operand literal is chosen by the
// column's Postgres type rather than by the operator: `{a,b}` for an array, `[1,3)` for a range,
// `{"a":1}` for jsonb. Mixing them is a 400.
//
// Only the array shape is type-checked (`where Value == [E]`), so `contains(["a"])` on a
// `String` column does not compile. A range and a jsonb column have no distinguishing Swift
// type to constrain on, so the range and JSON methods sit on bare
// `PostgrestFilterableExpression` and compile on any column; pairing one with the wrong column
// is a server error (`42883 operator does not exist`), not a wrong answer.

extension PostgrestFilterableExpression {
  /// Matches rows where this array column contains every element of `values`.
  ///
  /// An empty `values` matches every row whose column is non-null — the opposite of `in` and
  /// `likeAnyOf`, since every array contains the empty array.
  public func contains<E: PostgrestArrayElement>(_ values: [E]) -> PostgrestFilter<Root>
  where Value == [E] {
    PostgrestFilter(
      column: postgrestExpression, operator: "cs", value: postgrestArray(values))
  }

  /// Matches rows where every element of this array column is contained by `values`.
  public func containedBy<E: PostgrestArrayElement>(_ values: [E]) -> PostgrestFilter<Root>
  where Value == [E] {
    PostgrestFilter(
      column: postgrestExpression, operator: "cd", value: postgrestArray(values))
  }

  /// Matches rows where this array column shares at least one element with `values`.
  public func overlaps<E: PostgrestArrayElement>(_ values: [E]) -> PostgrestFilter<Root>
  where Value == [E] {
    PostgrestFilter(
      column: postgrestExpression, operator: "ov", value: postgrestArray(values))
  }
}

// MARK: - Range operands
//
// A range literal is taken as a string, and must stay a `.comparison` so `group()` escapes its
// `)`/`]`: bare, they close an enclosing `or=(…)` early and 400. The opposite of `in`.

extension PostgrestFilterableExpression {
  /// Matches rows where this range column contains `range`.
  ///
  /// - Parameter range: A Postgres range literal, for example `"[2,3)"`.
  public func containsRange(_ range: String) -> PostgrestFilter<Root> {
    PostgrestFilter(column: postgrestExpression, operator: "cs", value: range)
  }

  /// Matches rows where this range column is contained by `range`.
  public func containedByRange(_ range: String) -> PostgrestFilter<Root> {
    PostgrestFilter(column: postgrestExpression, operator: "cd", value: range)
  }

  /// Matches rows where this range column overlaps `range`.
  public func overlapsRange(_ range: String) -> PostgrestFilter<Root> {
    PostgrestFilter(column: postgrestExpression, operator: "ov", value: range)
  }

  /// Matches rows where this range column is strictly to the left of `range`.
  ///
  /// - Parameter range: A Postgres range literal, for example `"[2024-01-01,2024-02-01)"`.
  public func rangeLt(_ range: String) -> PostgrestFilter<Root> {
    PostgrestFilter(column: postgrestExpression, operator: "sl", value: range)
  }

  /// Matches rows where this range column is strictly to the right of `range`.
  public func rangeGt(_ range: String) -> PostgrestFilter<Root> {
    PostgrestFilter(column: postgrestExpression, operator: "sr", value: range)
  }

  /// Matches rows where this range column does not extend to the left of `range`.
  public func rangeGte(_ range: String) -> PostgrestFilter<Root> {
    PostgrestFilter(column: postgrestExpression, operator: "nxl", value: range)
  }

  /// Matches rows where this range column does not extend to the right of `range`.
  public func rangeLte(_ range: String) -> PostgrestFilter<Root> {
    PostgrestFilter(column: postgrestExpression, operator: "nxr", value: range)
  }

  /// Matches rows where this range column is adjacent to `range`.
  public func rangeAdjacent(_ range: String) -> PostgrestFilter<Root> {
    PostgrestFilter(column: postgrestExpression, operator: "adj", value: range)
  }
}

// MARK: - JSON operands

extension PostgrestFilterableExpression {
  /// Matches rows where this `jsonb` column contains `json`.
  ///
  /// - Parameter json: A JSON object literal, for example `#"{"a":1}"#`.
  public func containsJSON(_ json: String) -> PostgrestFilter<Root> {
    PostgrestFilter(column: postgrestExpression, operator: "cs", value: json)
  }

  /// Matches rows where this `jsonb` column is contained by `json`.
  public func containedByJSON(_ json: String) -> PostgrestFilter<Root> {
    PostgrestFilter(column: postgrestExpression, operator: "cd", value: json)
  }
}

// MARK: - Text search

extension PostgrestFilterableExpression where Value == String {
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
  ) -> PostgrestFilter<Root> {
    let configPart = config.map { "(\($0))" } ?? ""
    return PostgrestFilter(
      column: postgrestExpression,
      operator: "\(type?.rawValue ?? "")fts\(configPart)",
      value: query
    )
  }
}
