//
//  JSONTests.swift
//
//
//  Created by Guilherme Souza on 01/07/24.
//

import XCTest

@testable import PostgREST

final class JSONTests: XCTestCase {
  func testDecodeJSON() throws {
    let json = """
      {
        "created_at": "2024-06-15T18:12:04+00:00"
      }
      """.data(using: .utf8)!

    struct Value: Decodable {
      var createdAt: Date

      enum CodingKeys: String, CodingKey {
        case createdAt = "created_at"
      }
    }
    _ = try PostgrestClient.Configuration.jsonDecoder.decode(Value.self, from: json)
  }
}
