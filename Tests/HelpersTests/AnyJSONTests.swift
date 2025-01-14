//
//  AnyJSONTests.swift
//
//
//  Created by Guilherme Souza on 28/12/23.
//

import CustomDump
import Foundation
import XCTest

import Helpers

final class AnyJSONTests: XCTestCase {
  let jsonString = """
    {
      "array" : [
        1,
        2,
        3,
        4,
        5
      ],
      "bool" : true,
      "double" : 3.14,
      "integer" : 1,
      "null" : null,
      "object" : {
        "array" : [
          1,
          2,
          3,
          4,
          5
        ],
        "bool" : true,
        "double" : 3.14,
        "integer" : 1,
        "null" : null,
        "object" : {

        },
        "string" : "A string value"
      },
      "string" : "A string value"
    }
    """

  let jsonObject: AnyJSON = [
    "integer": 1,
    "double": 3.14,
    "string": "A string value",
    "bool": true,
    "null": nil,
    "array": [1, 2, 3, 4, 5],
    "object": [
      "integer": 1,
      "double": 3.14,
      "string": "A string value",
      "bool": true,
      "null": nil,
      "array": [1, 2, 3, 4, 5],
      "object": [:],
    ],
  ]

  func testDecode() throws {
    let data = try XCTUnwrap(jsonString.data(using: .utf8))
    let decodedJSON = try AnyJSON.decoder.decode(AnyJSON.self, from: data)

    expectNoDifference(decodedJSON, jsonObject)
  }

  func testEncode() throws {
    let encoder = AnyJSON.encoder
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

    let data = try encoder.encode(jsonObject)
    let decodedJSONString = try XCTUnwrap(String(data: data, encoding: .utf8))

    expectNoDifference(decodedJSONString, jsonString)
  }

  func testInitFromCodable() {
    try expectNoDifference(AnyJSON(jsonObject), jsonObject)

    let codableValue = CodableValue(
      integer: 1,
      double: 3.14,
      string: "A String value",
      bool: true,
      array: [1, 2, 3],
      dictionary: ["key": "value"],
      anyJSON: jsonObject
    )

    let json: AnyJSON = [
      "integer": 1,
      "double": 3.14,
      "string": "A String value",
      "bool": true,
      "array": [1, 2, 3],
      "dictionary": ["key": "value"],
      "any_json": jsonObject,
    ]

    try expectNoDifference(AnyJSON(codableValue), json)
    try expectNoDifference(codableValue, json.decode(as: CodableValue.self))
  }
}

struct CodableValue: Codable, Equatable {
  let integer: Int
  let double: Double
  let string: String
  let bool: Bool
  let array: [Int]
  let dictionary: [String: String]
  let anyJSON: AnyJSON

  enum CodingKeys: String, CodingKey {
    case integer
    case double
    case string
    case bool
    case array
    case dictionary
    case anyJSON = "any_json"
  }
}
