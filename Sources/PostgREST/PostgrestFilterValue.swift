public import Foundation
import Helpers

/// A value that can be used as a filter operand in PostgREST queries.
///
/// Types conforming to ``PostgrestFilterValue`` provide a ``rawValue`` string that is appended
/// directly to the PostgREST query string. The SDK ships with conformances for the most common
/// Swift types; you can add your own by conforming any `Encodable` type to this protocol.
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
/// | `Optional<Wrapped>` | `"NULL"` when `nil` |
public protocol PostgrestFilterValue {
  /// The string representation sent to PostgREST as the filter value.
  var rawValue: String { get }
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

/// An array of ``PostgrestFilterValue`` elements is itself a ``PostgrestFilterValue``.
///
/// The raw value is a PostgreSQL array literal, e.g. `{a,b,c}`.
extension Array: PostgrestFilterValue where Element: PostgrestFilterValue {
  public var rawValue: String {
    let elements = map { element -> String in
      if let element = element as? any PostgrestArrayLiteralElementEncodable {
        return element.postgrestArrayLiteralElement
      }
      return escapePostgRESTArrayLiteralElement(element.rawValue)
    }
    return "{\(elements.joined(separator: ","))}"
  }
}

/// An array of ``PostgrestFilterValue`` elements is itself a nested array literal
/// (e.g. `{1,2}`) when it appears as an element of another array, so it's passed
/// through unescaped rather than quoted as a scalar string.
extension Array: PostgrestArrayLiteralElementEncodable where Element: PostgrestFilterValue {
  package var postgrestArrayLiteralElement: String { rawValue }
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
}

/// `.null` is an actual SQL `NULL` array member, not the string `"NULL"`, and
/// `.array` is a nested array literal, not a scalar string — both are passed
/// through unescaped rather than quoted as a scalar.
extension JSONValue: PostgrestArrayLiteralElementEncodable {
  package var postgrestArrayLiteralElement: String {
    switch self {
    case .array(let array): array.postgrestArrayLiteralElement
    case .null: "NULL"
    case .object, .string, .double, .integer, .bool: escapePostgRESTArrayLiteralElement(rawValue)
    }
  }
}

/// An optional ``PostgrestFilterValue`` is itself a ``PostgrestFilterValue``.
///
/// When the optional is `nil`, the raw value is `"NULL"`.
extension Optional: PostgrestFilterValue where Wrapped: PostgrestFilterValue {
  public var rawValue: String {
    if let value = self {
      return value.rawValue
    }

    return "NULL"
  }
}

/// A `nil` optional is an actual SQL `NULL` array member, not the string
/// `"NULL"`, so it's passed through unescaped rather than quoted as a scalar.
extension Optional: PostgrestArrayLiteralElementEncodable where Wrapped: PostgrestFilterValue {
  package var postgrestArrayLiteralElement: String {
    guard let value = self else { return "NULL" }
    if let value = value as? any PostgrestArrayLiteralElementEncodable {
      return value.postgrestArrayLiteralElement
    }
    return escapePostgRESTArrayLiteralElement(value.rawValue)
  }
}

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
