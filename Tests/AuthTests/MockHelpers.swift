import ConcurrencyExtras
import Foundation
import TestHelpers

@testable import Auth

func json(named name: String) -> Data {
  let url = Bundle.module.url(forResource: name, withExtension: "json")
  return try! Data(contentsOf: url!)
}

extension Decodable {
  init(fromMockNamed name: String) {
    self = try! AuthClient.Configuration.jsonDecoder.decode(Self.self, from: json(named: name))
  }
}

extension CodeVerifierStorage {
  static var mock: CodeVerifierStorage {
    let code = LockIsolated<String?>(nil)

    return Self(
      get: { code.value },
      set: { code.setValue($0) }
    )
  }
}
