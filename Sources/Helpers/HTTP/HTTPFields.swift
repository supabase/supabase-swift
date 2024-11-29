import HTTPTypes

extension HTTPFields {
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
  package static let apiKey = HTTPField.Name("apiKey")!
}
