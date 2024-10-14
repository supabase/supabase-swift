import HTTPTypes

package extension HTTPFields {
  init(_ dictionary: [String: String]) {
    self.init(dictionary.map { .init(name: .init($0.key)!, value: $0.value) })
  }
  
  var dictionary: [String: String] {
    let keyValues = self.map {
      ($0.name.rawName, $0.value)
    }
    
    return .init(keyValues, uniquingKeysWith: { $1 })
  }
  
  mutating func merge(with other: Self) {
    for field in other {
      self[field.name] = field.value
    }
  }
  
  func merging(with other: Self) -> Self {
    var copy = self
    
    for field in other {
      copy[field.name] = field.value
    }

    return copy
  }
}

package extension HTTPField.Name {
  static let xClientInfo = HTTPField.Name("X-Client-Info")!
  static let xRegion = HTTPField.Name("x-region")!
  static let xRelayError = HTTPField.Name("x-relay-error")!
}
