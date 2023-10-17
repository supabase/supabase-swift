import Foundation
import Mocker

@testable import GoTrue

func json(named name: String) -> Data {
  let url = Bundle.module.url(forResource: name, withExtension: "json")
  return try! Data(contentsOf: url!)
}

extension Decodable {
  init(fromMockNamed name: String) {
    self = try! JSONDecoder.goTrue.decode(Self.self, from: json(named: name))
  }
}
