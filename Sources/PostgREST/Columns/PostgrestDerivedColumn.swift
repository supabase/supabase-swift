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
}

// The JSON paths need a `json`/`jsonb` column. The generator types exactly those as `JSONValue`,
// so `$0.duration.jsonText("k")` on an `interval` column does not compile, where the server would
// answer `42883 operator does not exist`.
extension _PostgrestColumnExpression where Value == JSONValue {
  /// Reads a `json`/`jsonb` object key as text, with `->>`.
  ///
  /// ```swift
  /// .where { $0.data.jsonText("name").eq("Ada") }   // data->>"name"=eq.Ada
  /// ```
  ///
  /// Comparison is textual, so `data->>"n"=gt.2` excludes a row where `n` is `10`. Use
  /// ``jsonObject(_:)-(String)`` for numeric comparison.
  ///
  /// Keeps the receiver's positions: a JSON path on a stored column filters and orders, one on a
  /// to-many embed does neither.
  ///
  /// - Parameter key: The object key to read. Always a key, even when it looks like a number:
  ///   `jsonText("0")` reads the key `"0"`. Use ``jsonText(_:)-(Int)`` for an array element.
  public func jsonText(_ key: String) -> _PostgrestDerivedExpression<Root, String, Position> {
    _deriving("->>\(quotedJSONKey(key))")
  }

  /// Reads a `json`/`jsonb` array element as text, with `->>`.
  ///
  /// - Parameter index: The zero-based array index. A negative index counts from the end.
  public func jsonText(_ index: Int) -> _PostgrestDerivedExpression<Root, String, Position> {
    _deriving("->>\(index)")
  }

  /// Reads a `json`/`jsonb` object key as JSON, with `->`.
  ///
  /// The result is a `JSONValue`, whatever the column decodes as, because `->` returns `jsonb`.
  /// It chains on, filters by containment, and compares as JSON: `.eq("1")` sends `eq."1"` and
  /// matches the string, `.eq(1)` the number. Numbers compare numerically, so `data->"n"=gt.2`
  /// includes a row where `n` is `10`.
  ///
  /// > Note: `jsonb` orders values of different types by type before value, and a number sorts
  /// > above a string, so `.gt("3")` matches a row where the value is the number `3`.
  ///
  /// - Parameter key: The object key to read. Always a key, even when it looks like a number.
  ///   Use ``jsonObject(_:)-(Int)`` for an array element.
  public func jsonObject(_ key: String) -> _PostgrestDerivedExpression<Root, JSONValue, Position> {
    _deriving("->\(quotedJSONKey(key))")
  }

  /// Reads a `json`/`jsonb` array element as JSON, with `->`.
  ///
  /// - Parameter index: The zero-based array index. A negative index counts from the end.
  public func jsonObject(_ index: Int) -> _PostgrestDerivedExpression<Root, JSONValue, Position> {
    _deriving("->\(index)")
  }
}

/// PostgREST reads a bare all-digit operand as an array index and stops at a `.`, so a key is
/// always quoted. Inside the quotes a backslash escapes the next character.
private func quotedJSONKey(_ key: String) -> String {
  var quoted = "\""
  for character in key {
    if character == "\\" || character == "\"" { quoted.append("\\") }
    quoted.append(character)
  }
  return quoted + "\""
}
