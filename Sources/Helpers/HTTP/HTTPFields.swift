import Foundation
package import HTTPTypes
import IssueReporting

extension HTTPFields {
  /// Builds fields from a `[String: String]`, dropping any entry whose key is not a valid HTTP
  /// field name.
  ///
  /// Some of these keys are dynamic, so a name RFC 9110 rejects (an empty string, one holding a
  /// space or a colon) must not trap. `HTTPResponse.init` builds fields straight from
  /// `response.allHeaderFields`, which the server and any proxy in front of it control, and
  /// `FunctionsClient.invoke` and `StorageFileApi` pass per-call headers. Dropping the bad entry
  /// and reporting keeps the remaining headers — and the response — usable.
  package init(_ dictionary: [String: String]) {
    self.init(
      dictionary.compactMap { key, value in
        guard let name = HTTPField.Name(key) else {
          reportIssue("Dropping header with invalid field name: \(key.debugDescription)")
          return nil
        }
        return HTTPField(name: name, value: value)
      }
    )
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

extension HTTPField.Name {
  package static let xClientInfo = HTTPField.Name("X-Client-Info")!
  package static let xRegion = HTTPField.Name("x-region")!
  package static let xRelayError = HTTPField.Name("x-relay-error")!
  package static let xRetryCount = HTTPField.Name("X-Retry-Count")!
}
