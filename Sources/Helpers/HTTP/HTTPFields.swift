import HTTPTypes

extension HTTPFields {
  package var dictionary: [String: String] {
    let keyValues = self.map {
      ($0.name.rawName, $0.value)
    }

    return .init(keyValues, uniquingKeysWith: { $1 })
  }

  package mutating func merge(
    _ other: Self,
    uniquingKeysWith combine: (String, String) throws -> String
  ) rethrows {
    self = try self.merging(other, uniquingKeysWith: combine)
  }

  package func merging(
    _ other: Self,
    uniquingKeysWith combine: (String, String) throws -> String
  ) rethrows -> HTTPFields {
    var copy = self

    for field in other {
      copy[field.name] = try combine(self[field.name] ?? "", field.value)
    }

    return copy
  }
}

extension HTTPField.Name {
  package static let xClientInfo = HTTPField.Name("X-Client-Info")!
  package static let xRegion = HTTPField.Name("x-region")!
  package static let xRelayError = HTTPField.Name("x-relay-error")!
  package static let apiKey = HTTPField.Name("apiKey")!
}
