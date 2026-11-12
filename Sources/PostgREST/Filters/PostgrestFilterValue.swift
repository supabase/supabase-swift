public import Foundation
import Helpers
import IssueReporting

/// A value that can appear as an element of a Postgres array literal, including SQL `NULL`.
///
/// This is the weaker of the two filter protocols, and the reason it exists separately from
/// ``PostgrestFilterValue`` is `nil`. A `NULL` is a perfectly good *array member* — `{1,NULL}` is a
/// real Postgres array — but it is not a value you can compare against, because `column = NULL` is
/// never true in SQL. So `Optional` conforms to this and deliberately **not** to
/// ``PostgrestFilterValue``, which is what makes `eq("col", value: nil)` fail to compile.
///
/// Every ``PostgrestFilterValue`` is automatically a `PostgrestArrayElement`, so a custom filter
/// value works inside an array with no extra conformance.
public protocol PostgrestArrayElement {
  /// This value's encoding when embedded inside a Postgres array literal.
  ///
  /// Distinct from ``PostgrestFilterValue/rawValue`` because a plain raw string cannot tell a real
  /// SQL `NULL` apart from the string `"NULL"`, nor a nested array literal from a `String` that
  /// merely looks like one (e.g. `"{a,b}"`).
  var postgrestArrayElement: String { get }
}

/// A value that can be used as a filter operand in PostgREST queries.
///
/// Types conforming to ``PostgrestFilterValue`` provide a ``rawValue`` string that is appended
/// directly to the PostgREST query string. The SDK ships with conformances for the most common
/// Swift types; you can add your own by conforming any type to this protocol.
///
/// > Important: `Optional` does **not** conform. To test for `NULL`, use ``PostgrestRequestBuilder/is(_:value:)``
/// > rather than an equality filter — see ``PostgrestArrayElement`` for why.
///
/// ## Built-in Conformances
///
/// | Swift type | Example `rawValue` |
/// |---|---|
/// | `String` | `"hello"` |
/// | `Int`, `Int16`, `Int32`, `Int64` | `"42"` |
/// | `Double`, `Float` | `"3.14"` |
/// | `Decimal` | `"9.99"` |
/// | `Bool` | `"true"` |
/// | `UUID` | `"123e4567-e89b-..."` |
/// | `Date` | `"2024-01-15T12:00:00.000Z"` |
/// | `[Element]` | `"{a,b,c}"` |
public protocol PostgrestFilterValue: PostgrestArrayElement {
  /// The string representation sent to PostgREST as the filter value.
  var rawValue: String { get }

  /// The operand the typed query API sends for this value, or `nil` when the value has no wire
  /// form. Defaults to ``rawValue``; the untyped builder always sends ``rawValue``.
  var _typedOperand: String? { get }
}

extension PostgrestFilterValue {
  /// The operand the typed query API sends for this value, which defaults to ``rawValue``.
  ///
  /// Implementation detail of the typed query API. Do not call it directly.
  public var _typedOperand: String? { rawValue }

  /// Escaping the raw value as a scalar is always correct for a non-`nil`, non-array value.
  public var postgrestArrayElement: String {
    escapePostgRESTArrayLiteralElement(rawValue)
  }
}

extension String: PostgrestFilterValue {
  /// The string itself, unchanged.
  public var rawValue: String { self }
}

extension Int: PostgrestFilterValue {
  /// The integer as decimal text, for example `"42"`.
  public var rawValue: String { "\(self)" }
}

extension Int16: PostgrestFilterValue {
  /// The integer as decimal text, for example `"42"`.
  public var rawValue: String { "\(self)" }
}

extension Int32: PostgrestFilterValue {
  /// The integer as decimal text, for example `"42"`.
  public var rawValue: String { "\(self)" }
}

extension Int64: PostgrestFilterValue {
  /// The integer as decimal text, for example `"42"`.
  public var rawValue: String { "\(self)" }
}

extension Double: PostgrestFilterValue {
  /// The number as text, for example `"3.14"`.
  public var rawValue: String { "\(self)" }
}

extension Float: PostgrestFilterValue {
  /// The number as text, for example `"3.14"`.
  public var rawValue: String { "\(self)" }
}

extension Decimal: PostgrestFilterValue {
  /// The number as text, for example `"9.99"`.
  public var rawValue: String { "\(self)" }
}

extension Bool: PostgrestFilterValue {
  /// The text `"true"` or `"false"`.
  public var rawValue: String { "\(self)" }
}

extension UUID: PostgrestFilterValue {
  /// The UUID string, in uppercase with hyphens.
  public var rawValue: String { uuidString }
}

extension Date: PostgrestFilterValue {
  /// The date in ISO 8601 form with fractional seconds, for example
  /// `"2024-01-15T12:00:00.000Z"`.
  public var rawValue: String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: self)
  }
}

extension Array: PostgrestFilterValue where Element: PostgrestArrayElement {
  /// The Postgres array literal for the elements, for example `"{a,b,c}"`.
  public var rawValue: String {
    "{\(map(\.postgrestArrayElement).joined(separator: ","))}"
  }
}

extension Array: PostgrestArrayElement where Element: PostgrestArrayElement {
  /// The nested Postgres array literal, which is the same text as ``rawValue``.
  public var postgrestArrayElement: String { rawValue }
}

extension JSONValue: PostgrestFilterValue {
  /// The filter form the untyped builder sends for this JSON value.
  ///
  /// A `.string` is sent bare, an `.array` as a Postgres array literal, an `.object` as JSON
  /// text, and `.null` as `NULL`.
  public var rawValue: String {
    switch self {
    case .array(let array): array.rawValue
    case .object(let object): object.rawValue
    case .string(let string): string.rawValue
    case .number(let number): number.description
    case .bool(let bool): bool.rawValue
    case .null: "NULL"
    }
  }

  /// The typed API only has a `JSONValue` operand on a `json`/`jsonb` expression, since the
  /// generator types no other column as `JSONValue`, and PostgREST reads that operand as JSON. So
  /// it is encoded as JSON here, where ``rawValue`` is the filter form the untyped builder sends —
  /// a `.string` bare, an `.array` as the Postgres literal `{20}`, `.null` as `NULL`.
  ///
  /// Only a `.number` that no Swift number type holds exactly fails to encode, and then this is `nil`. No operand stands in for
  /// it: `null` is a valid operand that matches JSON-null rows, so a `delete` would remove them.
  public var _typedOperand: String? {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return (try? encoder.encode(self)).map { String(decoding: $0, as: UTF8.self) }
  }

  /// `.null` is an actual SQL `NULL` array member, not the string `"NULL"`, and `.array` is a
  /// nested array literal, not a scalar string — both are passed through unescaped.
  public var postgrestArrayElement: String {
    switch self {
    case .array(let array): array.postgrestArrayElement
    case .null: "NULL"
    case .object, .string, .number, .bool:
      escapePostgRESTArrayLiteralElement(rawValue)
    }
  }
}

extension Optional: PostgrestArrayElement where Wrapped: PostgrestArrayElement {
  /// The wrapped value's array element encoding, or an unquoted SQL `NULL` for `nil`.
  public var postgrestArrayElement: String {
    guard let self else { return "NULL" }
    return self.postgrestArrayElement
  }
}

extension JSONObject: PostgrestArrayElement {}

extension JSONObject: PostgrestFilterValue {
  /// The object as JSON text with sorted keys, or `"{}"` when it cannot be serialized.
  public var rawValue: String {
    let value = mapValues(\.value)
    guard let serialized = JSONSerialization.stringify(value) else {
      reportIssue("Failed to serialize JSONObject as a PostgREST filter value.")
      return "{}"
    }
    return serialized
  }
}

extension JSONSerialization {
  static func stringify(_ object: Any) -> String? {
    let data = try? data(
      withJSONObject: object, options: [.withoutEscapingSlashes, .sortedKeys]
    )
    return data.flatMap { String(data: $0, encoding: .utf8) }
  }
}
