import Foundation
package import HTTPTypes

extension HTTPFields {
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

  /// Append or update a value in header.
  ///
  /// Example:
  /// ```swift
  /// var headers: HTTPFields = [
  ///   "Prefer": "count=exact,return=representation"
  /// ]
  ///
  /// headers.appendOrUpdate(.prefer, value: "return=minimal")
  /// #expect(headers == ["Prefer": "count=exact,return=minimal"]
  /// ```
  package mutating func appendOrUpdate(
    _ name: HTTPField.Name,
    value: String,
    separator: String = ","
  ) {
    if let currentValue = self[name] {
      var components = currentValue.components(separatedBy: separator)

      if let key = value.split(separator: "=").first,
        let index = components.firstIndex(where: {
          $0.trimmingCharacters(in: .whitespaces).hasPrefix("\(key)=")
        })
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

extension HTTPField.Name {
  /// `apikey`, the header that carries the project's API key to every Supabase service.
  public static let apikey = HTTPField.Name("apikey")!

  package static let xClientInfo = HTTPField.Name("X-Client-Info")!
  package static let xRetryCount = HTTPField.Name("X-Retry-Count")!
}
