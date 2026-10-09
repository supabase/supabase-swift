//
//  PostgrestDerivedColumn.swift
//  PostgREST
//
//  Created by Guilherme Souza on 26/08/26.
//

/// A Postgres type to cast to, paired with the Swift type that cast produces so the two cannot
/// disagree.
///
/// A type with no shipped target is still reachable: `_PostgrestCastTarget<String>("citext")`.
public struct _PostgrestCastTarget<Value>: Sendable {
  /// The Postgres type name, as it appears after `::`.
  public let sqlType: String

  /// Creates a target for a Postgres type this module does not ship.
  ///
  /// - Parameter sqlType: The Postgres type name, for example `"citext"`.
  public init(_ sqlType: String) {
    self.sqlType = sqlType
  }
}

extension _PostgrestCastTarget where Value == String {
  /// `::text`
  public static var text: _PostgrestCastTarget<String> { _PostgrestCastTarget("text") }
}

extension _PostgrestCastTarget where Value == Int {
  /// `::int`
  public static var int: _PostgrestCastTarget<Int> { _PostgrestCastTarget("int") }
}

extension _PostgrestCastTarget where Value == Double {
  /// `::double precision`
  public static var double: _PostgrestCastTarget<Double> {
    _PostgrestCastTarget("double precision")
  }
}

extension _PostgrestCastTarget where Value == Bool {
  /// `::boolean`
  public static var boolean: _PostgrestCastTarget<Bool> { _PostgrestCastTarget("boolean") }
}

extension _PostgrestColumnExpression {
  /// Casts this expression to another Postgres type.
  ///
  /// ```swift
  /// Item.columns.cost.cast(to: .text).postgrestExpression   // "cost::text"
  /// ```
  ///
  /// PostgREST accepts `cost::text=eq.10` and then drops the cast, so a filter on a cast silently
  /// compares the uncast column; ordering by one is a 400. The result is therefore **select
  /// position only**, whatever it was applied to.
  ///
  /// > Note: Make a cast the **last** step in a chain. PostgREST applies only the first cast in
  /// > `cost::text::int`, and rejects a JSON path applied to a cast (`cost::text->>k`).
  ///
  /// - Parameter target: The Postgres type to cast to.
  public func cast<T>(
    to target: _PostgrestCastTarget<T>
  ) -> _PostgrestDerivedExpression<Root, T, _PostgrestSelectOnly> {
    _deriving("::\(target.sqlType)")
  }

  /// Reads a `json`/`jsonb` path as text, with `->>`.
  ///
  /// ```swift
  /// .where { $0.data.jsonText("name").eq("Ada") }   // data->>name=eq.Ada
  /// ```
  ///
  /// Comparison is textual, so `data->>n=gt.2` excludes a row where `n` is `10`. Use
  /// ``jsonObject(_:)`` for numeric comparison.
  ///
  /// Keeps the receiver's positions: a JSON path on a stored column filters and orders, one on a
  /// to-many embed does neither.
  ///
  /// - Parameter path: The key or index to read.
  public func jsonText(_ path: String) -> _PostgrestDerivedExpression<Root, String, Position> {
    _deriving("->>\(path)")
  }

  /// Reads a `json`/`jsonb` path as JSON, with `->`.
  ///
  /// Comparison is numeric for numbers, so `data->n=gt.2` includes a row where `n` is `10`.
  ///
  /// > Note: Meant to be chained onward, not selected directly. The result keeps the receiver's
  /// > `Value`, but `->` returns raw `jsonb`, which generally will not decode as that type —
  /// > chain ``jsonText(_:)`` or ``cast(to:)`` to reach a scalar.
  ///
  /// - Parameter path: The key or index to read.
  public func jsonObject(_ path: String) -> _PostgrestDerivedExpression<Root, Value, Position> {
    _deriving("->\(path)")
  }
}
