import Alamofire
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
    self = try! JSONDecoder.supabase().decode(Self.self, from: json(named: name))
  }
}
