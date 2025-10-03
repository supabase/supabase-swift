import Alamofire

extension HTTPHeaders {
  package func merging(with other: Self) -> Self {
    var copy = self
    copy.merge(with: other)
    return copy
  }

  package mutating func merge(with other: Self) {
    for field in other {
      self[field.name] = field.value
    }
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
