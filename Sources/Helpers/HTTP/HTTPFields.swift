import Alamofire
import HTTPTypes

extension HTTPFields {
  package init(_ dictionary: [String: String]) {
    self.init(dictionary.map { .init(name: .init($0.key)!, value: $0.value) })
  }

  package var dictionary: [String: String] {
    let keyValues = self.map {
      ($0.name.rawName, $0.value)
    }

    return .init(keyValues, uniquingKeysWith: { $1 })
  }

  package mutating func merge(with other: Self) {
    for field in other {
      self[field.name] = field.value
    }
  }

  package func merging(with other: Self) -> Self {
    var copy = self

    for field in other {
      copy[field.name] = field.value
    }

    return copy
  }

}

extension HTTPField.Name {
  package static let xClientInfo = HTTPField.Name("X-Client-Info")!
  package static let xRegion = HTTPField.Name("x-region")!
  package static let xRelayError = HTTPField.Name("x-relay-error")!
}

extension HTTPHeaders {
  package func merging(with other: Self) -> Self {
    var copy = self

    for field in other {
      copy[field.name] = field.value
    }

    return copy
  }

  /// Append or update a value in header.
  ///
  /// Example:
  /// ```swift
  /// var headers: HTTPHeaders = [
  ///   "Prefer": "count=exact,return=representation"
  /// ]
  ///
  /// headers.appendOrUpdate("Prefer", value: "return=minimal")
  /// #expect(headers == ["Prefer": "count=exact,return=minimal"]
  /// ```
  package mutating func appendOrUpdate(
    _ name: String,
    value: String,
    separator: String = ","
  ) {
    if let currentValue = self[name] {
      var components = currentValue.components(separatedBy: separator)

      if let key = value.split(separator: "=").first,
        let index = components.firstIndex(where: { $0.hasPrefix("\(key)=") })
      {
        components[index] = value
      } else {
        components.append(value)
      }

      self[name] = components.joined(separator: separator)
    } else {
      self[name] = value
    }
  }
}
