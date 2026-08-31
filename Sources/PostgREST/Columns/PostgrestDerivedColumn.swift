//
//  PostgrestDerivedColumn.swift
//  PostgREST
//
//  Created by Guilherme Souza on 26/08/26.
//

/// A column with a cast applied — **select position only**.
///
/// PostgREST accepts `cost::text=eq.10` and then drops the cast, so a filter on a cast silently
/// compares the uncast column; ordering by one is a 400. Only `select=cost::text` behaves as
/// written, so this conforms to ``PostgrestColumnExpression`` and neither refinement.
///
/// To *filter* on a cast, expose it from the database as a generated column or a view; it is then
/// an ordinary column, usable in every position.
public struct PostgrestCastColumn<
  Root: PostgrestRelation,
  Value
>: PostgrestColumnExpression {
  public let postgrestExpression: String

  init(_ expression: String) {
    self.postgrestExpression = expression
  }
}

/// A JSON path into a `json`/`jsonb` column. Unlike a cast, usable in select, filter and order
/// position alike.
///
/// > Important: The arrow decides the comparison semantics. `->>` yields `text`, so
/// > `data->>n=gt.2` compares as text and excludes `10`; `->` yields `jsonb`, which compares
/// > numerically and includes it.
public struct PostgrestJSONPath<
  Root: PostgrestRelation,
  Value
>: PostgrestFilterableExpression, PostgrestOrderableExpression {
  public let postgrestExpression: String

  init(_ expression: String) {
    self.postgrestExpression = expression
  }
}

/// A Postgres type to cast to, paired with the Swift type that cast produces so the two cannot
/// disagree.
///
/// A type with no shipped target is still reachable: `PostgrestCastTarget<String>("citext")`.
public struct PostgrestCastTarget<Value>: Sendable {
  /// The Postgres type name, as it appears after `::`.
  public let sqlType: String

  /// Creates a target for a Postgres type this module does not ship.
  ///
  /// - Parameter sqlType: The Postgres type name, for example `"citext"`.
  public init(_ sqlType: String) {
    self.sqlType = sqlType
  }
}

extension PostgrestCastTarget where Value == String {
  /// `::text`
  public static var text: PostgrestCastTarget<String> { PostgrestCastTarget("text") }
}

extension PostgrestCastTarget where Value == Int {
  /// `::int`
  public static var int: PostgrestCastTarget<Int> { PostgrestCastTarget("int") }
}

extension PostgrestCastTarget where Value == Double {
  /// `::double precision`
  public static var double: PostgrestCastTarget<Double> {
    PostgrestCastTarget("double precision")
  }
}

extension PostgrestCastTarget where Value == Bool {
  /// `::boolean`
  public static var boolean: PostgrestCastTarget<Bool> { PostgrestCastTarget("boolean") }
}

extension PostgrestColumnExpression {
  /// Casts this expression to another Postgres type.
  ///
  /// ```swift
  /// Item.columns.cost.cast(to: .text).postgrestExpression   // "cost::text", valid in a select list
  /// ```
  ///
  /// > Important: The result is **select position only** — it cannot be filtered or ordered by.
  ///
  /// > Note: Make a cast the **last** step in a chain. PostgREST applies only the first cast in
  /// > `cost::text::int`, and rejects a JSON path applied to a cast (`cost::text->>k`).
  ///
  /// - Parameter target: The Postgres type to cast to.
  /// - Returns: A select-only cast column rendering `expression::sqlType`.
  public func cast<T>(to target: PostgrestCastTarget<T>) -> PostgrestCastColumn<Root, T> {
    PostgrestCastColumn("\(postgrestExpression)::\(target.sqlType)")
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
  /// - Parameter path: The key or index to read.
  /// - Returns: A JSON path typed `String`, because `->>` always yields text.
  public func jsonText(_ path: String) -> PostgrestJSONPath<Root, String> {
    PostgrestJSONPath("\(postgrestExpression)->>\(path)")
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
  /// - Returns: A JSON path rendering `expression->path`.
  public func jsonObject(_ path: String) -> PostgrestJSONPath<Root, Value> {
    PostgrestJSONPath("\(postgrestExpression)->\(path)")
  }
}
