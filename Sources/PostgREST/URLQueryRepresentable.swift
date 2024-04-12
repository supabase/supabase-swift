import Foundation

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

extension Array: URLQueryRepresentable where Element: URLQueryRepresentable {
  public var queryValue: String {
    "{\(map(\.queryValue).joined(separator: ","))}"
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

extension Dictionary: URLQueryRepresentable
  where
  Key: URLQueryRepresentable,
  Value: URLQueryRepresentable
{
  public var queryValue: String {
    JSONSerialization.stringfy(self)
  }
}

extension JSONSerialization {
  static func stringfy(_ object: Any) -> String {
    guard
      let data = try? data(
        withJSONObject: object, options: [.withoutEscapingSlashes, .sortedKeys]
      ),
      let string = String(data: data, encoding: .utf8)
    else {
      return "{}"
    }
    return string
  }
}
