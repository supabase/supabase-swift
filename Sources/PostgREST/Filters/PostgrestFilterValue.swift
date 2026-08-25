public import Foundation
import Helpers

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
/// | `Int` | `"42"` |
/// | `Double` | `"3.14"` |
/// | `Bool` | `"true"` |
/// | `UUID` | `"123e4567-e89b-..."` |
/// | `Date` | `"2024-01-15T12:00:00.000Z"` |
/// | `[Element]` | `"{a,b,c}"` |
public protocol PostgrestFilterValue: PostgrestArrayElement {
  /// The string representation sent to PostgREST as the filter value.
  var rawValue: String { get }
}

extension PostgrestFilterValue {
  /// Escaping the raw value as a scalar is always correct for a non-`nil`, non-array value.
  public var postgrestArrayElement: String {
    escapePostgRESTArrayLiteralElement(rawValue)
  }
}

/// `String` can be used directly as a PostgREST filter value.
extension String: PostgrestFilterValue {
  public var rawValue: String { self }
}

/// `Int` can be used directly as a PostgREST filter value.
extension Int: PostgrestFilterValue {
  public var rawValue: String { "\(self)" }
}

/// `Double` can be used directly as a PostgREST filter value.
extension Double: PostgrestFilterValue {
  public var rawValue: String { "\(self)" }
}

/// `Bool` can be used directly as a PostgREST filter value.
extension Bool: PostgrestFilterValue {
  public var rawValue: String { "\(self)" }
}

/// `UUID` can be used directly as a PostgREST filter value.
extension UUID: PostgrestFilterValue {
  public var rawValue: String { uuidString }
}

/// `Date` can be used directly as a PostgREST filter value, formatted as an ISO 8601 string.
extension Date: PostgrestFilterValue {
  public var rawValue: String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: self)
  }
}

/// An array of ``PostgrestArrayElement`` values is itself a ``PostgrestFilterValue``.
///
/// The raw value is a Postgres array literal, e.g. `{a,b,c}`. Because the element only needs to be
/// a ``PostgrestArrayElement``, an array may contain `nil` — `{1,NULL}` — even though `nil` cannot
/// be used as a filter operand on its own.
extension Array: PostgrestFilterValue where Element: PostgrestArrayElement {
  public var rawValue: String {
    "{\(map(\.postgrestArrayElement).joined(separator: ","))}"
  }
}

/// A nested array is already an array literal, so it is passed through unescaped rather than
/// quoted as a scalar string.
extension Array: PostgrestArrayElement where Element: PostgrestArrayElement {
  public var postgrestArrayElement: String { rawValue }
}

/// `JSONValue` can be used directly as a PostgREST filter value.
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

/// An optional value is a Postgres array member, but **not** a filter operand.
///
/// `nil` encodes as `NULL` inside an array literal. It conforms to ``PostgrestArrayElement`` only,
/// so passing it to `eq`, `neq`, `gt` and friends is a compile error rather than a query that
/// silently matches the wrong rows.
extension Optional: PostgrestArrayElement where Wrapped: PostgrestArrayElement {
  public var postgrestArrayElement: String {
    guard let self else { return "NULL" }
    return self.postgrestArrayElement
  }
}

extension JSONObject: PostgrestArrayElement {}

/// `JSONObject` can be used directly as a PostgREST filter value.
extension JSONObject: PostgrestFilterValue {
  public var rawValue: String {
    let value = mapValues(\.value)
    return JSONSerialization.stringify(value)!
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
