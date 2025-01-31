import Foundation
import Helpers

/// A type that can fit into the query part of a URL.
public protocol URLQueryRepresentable {
  /// A String representation of this instance that can fit as a query parameter's value.
  var queryValue: String { get }
}

extension String: URLQueryRepresentable {
  public var queryValue: String { self }
}

extension Int: URLQueryRepresentable {
  public var queryValue: String { "\(self)" }
}

extension Double: URLQueryRepresentable {
  public var queryValue: String { "\(self)" }
}

extension Bool: URLQueryRepresentable {
  public var queryValue: String { "\(self)" }
}

extension UUID: URLQueryRepresentable {
  public var queryValue: String { uuidString }
}

extension Date: URLQueryRepresentable {
  public var queryValue: String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: self)
  }
}

extension Array: URLQueryRepresentable where Element: URLQueryRepresentable {
  public var queryValue: String {
    "{\(map(\.queryValue).joined(separator: ","))}"
  }
}

extension AnyJSON: URLQueryRepresentable {
  public var queryValue: String {
    switch self {
    case let .array(array): array.queryValue
    case let .object(object): object.queryValue
    case let .string(string): string.queryValue
    case let .double(double): double.queryValue
    case let .integer(integer): integer.queryValue
    case let .bool(bool): bool.queryValue
    case .null: "NULL"
    }
  }
}

extension Optional: URLQueryRepresentable where Wrapped: URLQueryRepresentable {
  public var queryValue: String {
    if let value = self {
      return value.queryValue
    }

    return "NULL"
  }
}

extension JSONObject: URLQueryRepresentable {
  public var queryValue: String {
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
