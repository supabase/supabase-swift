import Foundation

/// A value that can be used to filter Postgrest queries.
public protocol PostgrestFilterValue {
  var rawValue: String { get }
}

extension String: PostgrestFilterValue {
  public var rawValue: String { self }
}

extension Int: PostgrestFilterValue {
  public var rawValue: String { "\(self)" }
}

extension Double: PostgrestFilterValue {
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

extension Array: PostgrestFilterValue where Element: PostgrestFilterValue {
  public var rawValue: String {
    "{\(map(\.rawValue).joined(separator: ","))}"
  }
}

extension AnyJSON: PostgrestFilterValue {
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

extension Optional: PostgrestFilterValue where Wrapped: PostgrestFilterValue {
  public var rawValue: String {
    if let value = self {
      return value.rawValue
    }

    return "NULL"
  }
}

extension JSONObject: PostgrestFilterValue {
  public var rawValue: String {
    let value = mapValues(\.value)
    return JSONSerialization.stringfy(value)!
  }
}

extension JSONSerialization {
  static func stringfy(_ object: Any) -> String? {
    let data = try? data(
      withJSONObject: object, options: [.withoutEscapingSlashes, .sortedKeys]
    )
    return data.flatMap { String(data: $0, encoding: .utf8) }
  }
}
