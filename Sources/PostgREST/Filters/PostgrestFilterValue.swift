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
  public var _typedOperand: String? { rawValue }

  /// Escaping the raw value as a scalar is always correct for a non-`nil`, non-array value.
  public var postgrestArrayElement: String {
    escapePostgRESTArrayLiteralElement(rawValue)
  }
}

extension String: PostgrestFilterValue {
  public var rawValue: String { self }
}

extension Int: PostgrestFilterValue {
  public var rawValue: String { "\(self)" }
}

extension Int16: PostgrestFilterValue {
  public var rawValue: String { "\(self)" }
}

extension Int32: PostgrestFilterValue {
  public var rawValue: String { "\(self)" }
}

extension Int64: PostgrestFilterValue {
  public var rawValue: String { "\(self)" }
}

extension Double: PostgrestFilterValue {
  public var rawValue: String { "\(self)" }
}

extension Float: PostgrestFilterValue {
  public var rawValue: String { "\(self)" }
}

extension Decimal: PostgrestFilterValue {
  public var rawValue: String { "\(self)" }
}

extension Bool: PostgrestFilterValue {
  public var rawValue: String { "\(self)" }
}

extension UUID: PostgrestFilterValue {
  public var rawValue: String { uuidString }
}

extension Date: PostgrestFilterValue {
  public var rawValue: String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: self)
  }
}

extension Array: PostgrestFilterValue where Element: PostgrestArrayElement {
  public var rawValue: String {
    "{\(map(\.postgrestArrayElement).joined(separator: ","))}"
  }
}

extension Array: PostgrestArrayElement where Element: PostgrestArrayElement {
  public var postgrestArrayElement: String { rawValue }
}

extension JSONValue: PostgrestFilterValue {
  public var rawValue: String {
    switch self {
    case .array(let array): array.rawValue
    case .object(let object): object.rawValue
    case .string(let string): string.rawValue
    case .double(let double): double.rawValue
    case .integer(let integer): integer.rawValue
    case .bool(let bool): bool.rawValue
    case .null: "NULL"
    }
  }

  /// The typed API only has a `JSONValue` operand on a `json`/`jsonb` expression, since the
  /// generator types no other column as `JSONValue`, and PostgREST reads that operand as JSON. So
  /// it is encoded as JSON here, where ``rawValue`` is the filter form the untyped builder sends —
  /// a `.string` bare, an `.array` as the Postgres literal `{20}`, `.null` as `NULL`.
  ///
  /// Only a non-finite `.double` fails to encode, and then this is `nil`. No operand stands in for
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
    case .object, .string, .double, .integer, .bool:
      escapePostgRESTArrayLiteralElement(rawValue)
    }
  }
}

extension Optional: PostgrestArrayElement where Wrapped: PostgrestArrayElement {
  public var postgrestArrayElement: String {
    guard let self else { return "NULL" }
    return self.postgrestArrayElement
  }
}

extension JSONObject: PostgrestArrayElement {}

extension JSONObject: PostgrestFilterValue {
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
