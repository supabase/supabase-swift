//
//  NullEncodableTests.swift
//
//
//  Created by Guilherme Souza on 19/12/23.
//

import PostgREST
import XCTest

final class NullEncodableTests: XCTestCase {
  struct Item: Encodable {
    var email: String
    @NullEncodable var username: String?
  }

  func testEncode() throws {
    let items = [
      Item(email: "example@mail.com", username: .init(wrappedValue: "example")),
      Item(email: "example2@mail.com", username: .init(wrappedValue: nil)),
      Item(email: "example3@mail.com", username: .init(wrappedValue: "example3")),
    ]

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(items)
    let jsonString = try XCTUnwrap(String(data: data, encoding: .utf8))

    XCTAssertEqual(
      jsonString,
      """
      [
        {
          "email" : "example@mail.com",
          "username" : "example"
        },
        {
          "email" : "example2@mail.com",
          "username" : null
        },
        {
          "email" : "example3@mail.com",
          "username" : "example3"
        }
      ]
      """
    )
  }
}
