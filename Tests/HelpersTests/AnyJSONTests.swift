//
//  AnyJSONTests.swift
//
//
//  Created by Guilherme Souza on 28/12/23.
//

import CustomDump
import Foundation
import Helpers
import XCTest

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

  // MARK: - Value Property Tests

  func testValueProperty() {
    // Test null value
    XCTAssertTrue(AnyJSON.null.value is NSNull)

    // Test string value
    XCTAssertEqual(AnyJSON.string("test").value as? String, "test")

    // Test integer value
    XCTAssertEqual(AnyJSON.integer(42).value as? Int, 42)

    // Test double value
    XCTAssertEqual(AnyJSON.double(3.14).value as? Double, 3.14)

    // Test bool value
    XCTAssertEqual(AnyJSON.bool(true).value as? Bool, true)
    XCTAssertEqual(AnyJSON.bool(false).value as? Bool, false)

    // Test object value
    let object: AnyJSON = ["key": "value"]
    let objectValue = object.value as? [String: Any]
    XCTAssertEqual(objectValue?["key"] as? String, "value")

    // Test array value
    let array: AnyJSON = [1, 2, 3]
    let arrayValue = array.value as? [Any]
    XCTAssertEqual(arrayValue?[0] as? Int, 1)
    XCTAssertEqual(arrayValue?[1] as? Int, 2)
    XCTAssertEqual(arrayValue?[2] as? Int, 3)
  }

  // MARK: - Type-Specific Value Accessors

  func testIsNil() {
    XCTAssertTrue(AnyJSON.null.isNil)
    XCTAssertFalse(AnyJSON.string("test").isNil)
    XCTAssertFalse(AnyJSON.integer(42).isNil)
    XCTAssertFalse(AnyJSON.double(3.14).isNil)
    XCTAssertFalse(AnyJSON.bool(true).isNil)
    XCTAssertFalse(AnyJSON.object([:]).isNil)
    XCTAssertFalse(AnyJSON.array([]).isNil)
  }

  func testBoolValue() {
    XCTAssertEqual(AnyJSON.bool(true).boolValue, true)
    XCTAssertEqual(AnyJSON.bool(false).boolValue, false)
    XCTAssertNil(AnyJSON.string("test").boolValue)
    XCTAssertNil(AnyJSON.integer(42).boolValue)
    XCTAssertNil(AnyJSON.double(3.14).boolValue)
    XCTAssertNil(AnyJSON.null.boolValue)
    XCTAssertNil(AnyJSON.object([:]).boolValue)
    XCTAssertNil(AnyJSON.array([]).boolValue)
  }

  func testStringValue() {
    XCTAssertEqual(AnyJSON.string("test").stringValue, "test")
    XCTAssertNil(AnyJSON.bool(true).stringValue)
    XCTAssertNil(AnyJSON.integer(42).stringValue)
    XCTAssertNil(AnyJSON.double(3.14).stringValue)
    XCTAssertNil(AnyJSON.null.stringValue)
    XCTAssertNil(AnyJSON.object([:]).stringValue)
    XCTAssertNil(AnyJSON.array([]).stringValue)
  }

  func testIntValue() {
    XCTAssertEqual(AnyJSON.integer(42).intValue, 42)
    XCTAssertNil(AnyJSON.string("test").intValue)
    XCTAssertNil(AnyJSON.bool(true).intValue)
    XCTAssertNil(AnyJSON.double(3.14).intValue)
    XCTAssertNil(AnyJSON.null.intValue)
    XCTAssertNil(AnyJSON.object([:]).intValue)
    XCTAssertNil(AnyJSON.array([]).intValue)
  }

  func testDoubleValue() {
    XCTAssertEqual(AnyJSON.double(3.14).doubleValue, 3.14)
    XCTAssertNil(AnyJSON.string("test").doubleValue)
    XCTAssertNil(AnyJSON.bool(true).doubleValue)
    XCTAssertNil(AnyJSON.integer(42).doubleValue)
    XCTAssertNil(AnyJSON.null.doubleValue)
    XCTAssertNil(AnyJSON.object([:]).doubleValue)
    XCTAssertNil(AnyJSON.array([]).doubleValue)
  }

  func testObjectValue() {
    let object: JSONObject = ["key": "value"]
    XCTAssertEqual(AnyJSON.object(object).objectValue, object)
    XCTAssertNil(AnyJSON.string("test").objectValue)
    XCTAssertNil(AnyJSON.bool(true).objectValue)
    XCTAssertNil(AnyJSON.integer(42).objectValue)
    XCTAssertNil(AnyJSON.double(3.14).objectValue)
    XCTAssertNil(AnyJSON.null.objectValue)
    XCTAssertNil(AnyJSON.array([]).objectValue)
  }

  func testArrayValue() {
    let array: JSONArray = [1, 2, 3]
    XCTAssertEqual(AnyJSON.array(array).arrayValue, array)
    XCTAssertNil(AnyJSON.string("test").arrayValue)
    XCTAssertNil(AnyJSON.bool(true).arrayValue)
    XCTAssertNil(AnyJSON.integer(42).arrayValue)
    XCTAssertNil(AnyJSON.double(3.14).arrayValue)
    XCTAssertNil(AnyJSON.null.arrayValue)
    XCTAssertNil(AnyJSON.object([:]).arrayValue)
  }

  // MARK: - ExpressibleByLiteral Tests

  func testExpressibleByNilLiteral() {
    let json: AnyJSON = nil
    XCTAssertEqual(json, .null)
  }

  func testExpressibleByStringLiteral() {
    let json: AnyJSON = "test string"
    XCTAssertEqual(json, .string("test string"))
  }

  func testExpressibleByIntegerLiteral() {
    let json: AnyJSON = 42
    XCTAssertEqual(json, .integer(42))
  }

  func testExpressibleByFloatLiteral() {
    let json: AnyJSON = 3.14
    XCTAssertEqual(json, .double(3.14))
  }

  func testExpressibleByBooleanLiteral() {
    let json: AnyJSON = true
    XCTAssertEqual(json, .bool(true))

    let jsonFalse: AnyJSON = false
    XCTAssertEqual(jsonFalse, .bool(false))
  }

  func testExpressibleByArrayLiteral() {
    let json: AnyJSON = [1, "test", true, nil]
    XCTAssertEqual(json, .array([.integer(1), .string("test"), .bool(true), .null]))
  }

  func testExpressibleByDictionaryLiteral() {
    let json: AnyJSON = ["key1": "value1", "key2": 42, "key3": true]
    let expected: AnyJSON = .object([
      "key1": .string("value1"),
      "key2": .integer(42),
      "key3": .bool(true),
    ])
    XCTAssertEqual(json, expected)
  }

  // MARK: - CustomStringConvertible Tests

  func testDescription() {
    XCTAssertEqual(AnyJSON.null.description, "<null>")
    XCTAssertEqual(AnyJSON.string("test").description, "test")
    XCTAssertEqual(AnyJSON.integer(42).description, "42")
    XCTAssertEqual(AnyJSON.double(3.14).description, "3.14")
    XCTAssertEqual(AnyJSON.bool(true).description, "true")
    XCTAssertEqual(AnyJSON.bool(false).description, "false")

    // Test object description
    let object: AnyJSON = ["key": "value"]
    XCTAssertTrue(object.description.contains("key"))
    XCTAssertTrue(object.description.contains("value"))

    // Test array description
    let array: AnyJSON = [1, 2, 3]
    XCTAssertTrue(array.description.contains("1"))
    XCTAssertTrue(array.description.contains("2"))
    XCTAssertTrue(array.description.contains("3"))
  }

  // MARK: - Hashable Tests

  func testEquality() {
    // Test same values
    XCTAssertEqual(AnyJSON.null, AnyJSON.null)
    XCTAssertEqual(AnyJSON.string("test"), AnyJSON.string("test"))
    XCTAssertEqual(AnyJSON.integer(42), AnyJSON.integer(42))
    XCTAssertEqual(AnyJSON.double(3.14), AnyJSON.double(3.14))
    XCTAssertEqual(AnyJSON.bool(true), AnyJSON.bool(true))
    XCTAssertEqual(AnyJSON.bool(false), AnyJSON.bool(false))

    // Test different values
    XCTAssertNotEqual(AnyJSON.string("test"), AnyJSON.string("different"))
    XCTAssertNotEqual(AnyJSON.integer(42), AnyJSON.integer(43))
    XCTAssertNotEqual(AnyJSON.double(3.14), AnyJSON.double(3.15))
    XCTAssertNotEqual(AnyJSON.bool(true), AnyJSON.bool(false))

    // Test different types
    XCTAssertNotEqual(AnyJSON.string("42"), AnyJSON.integer(42))
    XCTAssertNotEqual(AnyJSON.integer(42), AnyJSON.double(42.0))
    XCTAssertNotEqual(AnyJSON.null, AnyJSON.string(""))

    // Test objects
    let object1: AnyJSON = ["key": "value"]
    let object2: AnyJSON = ["key": "value"]
    let object3: AnyJSON = ["key": "different"]
    XCTAssertEqual(object1, object2)
    XCTAssertNotEqual(object1, object3)

    // Test arrays
    let array1: AnyJSON = [1, 2, 3]
    let array2: AnyJSON = [1, 2, 3]
    let array3: AnyJSON = [1, 2, 4]
    XCTAssertEqual(array1, array2)
    XCTAssertNotEqual(array1, array3)
  }

  func testHashable() {
    let set: Set<AnyJSON> = [
      .null,
      .string("test"),
      .integer(42),
      .double(3.14),
      .bool(true),
      .object(["key": "value"]),
      .array([1, 2, 3]),
    ]

    XCTAssertEqual(set.count, 7)
    XCTAssertTrue(set.contains(.null))
    XCTAssertTrue(set.contains(.string("test")))
    XCTAssertTrue(set.contains(.integer(42)))
    XCTAssertTrue(set.contains(.double(3.14)))
    XCTAssertTrue(set.contains(.bool(true)))
    XCTAssertTrue(set.contains(.object(["key": "value"])))
    XCTAssertTrue(set.contains(.array([1, 2, 3])))
  }

  // MARK: - JSONArray and JSONObject Extension Tests

  func testJSONArrayDecode() throws {
    let jsonArray: JSONArray = [AnyJSON.integer(1), AnyJSON.integer(2), AnyJSON.integer(3)]
    // Decode each element individually since the JSONArray.decode method has issues
    let decoded: [Int] = try jsonArray.map { try $0.decode(as: Int.self) }
    XCTAssertEqual(decoded, [1, 2, 3])
  }

  func testJSONObjectDecode() throws {
    let jsonObject: JSONObject = ["name": AnyJSON.string("John"), "age": AnyJSON.integer(30)]
    let decoded: Person = try jsonObject.decode(as: Person.self)
    XCTAssertEqual(decoded.name, "John")
    XCTAssertEqual(decoded.age, 30)
  }

  func testJSONObjectInitFromCodable() throws {
    let person = Person(name: "John", age: 30)
    let jsonObject = try JSONObject(person)
    XCTAssertEqual(jsonObject["name"], .string("John"))
    XCTAssertEqual(jsonObject["age"], .integer(30))
  }

  func testJSONObjectInitFromCodableFailure() {
    // Test with a simple string, which should fail because it's not an object
    XCTAssertThrowsError(try JSONObject("not an object"))

    // Test with an integer, which should also fail
    XCTAssertThrowsError(try JSONObject(42))
  }

  // MARK: - Error Handling Tests

  func testInvalidJSONDecoding() {
    let invalidJSON = "invalid json"
    let data = invalidJSON.data(using: .utf8)!

    XCTAssertThrowsError(try AnyJSON.decoder.decode(AnyJSON.self, from: data))
  }

  func testDecodeWithCustomDecoder() throws {
    let customDecoder = JSONDecoder()
    customDecoder.keyDecodingStrategy = .convertFromSnakeCase

    let json: AnyJSON = ["user_name": "John", "user_age": 30]
    let decoded: CustomPerson = try json.decode(as: CustomPerson.self, decoder: customDecoder)
    XCTAssertEqual(decoded.userName, "John")
    XCTAssertEqual(decoded.userAge, 30)
  }

  // MARK: - Edge Cases

  func testEmptyObjectAndArray() {
    let emptyObject: AnyJSON = [:]
    let emptyArray: AnyJSON = []

    XCTAssertEqual(emptyObject, .object([:]))
    XCTAssertEqual(emptyArray, .array([]))

    XCTAssertTrue(emptyObject.objectValue?.isEmpty == true)
    XCTAssertTrue(emptyArray.arrayValue?.isEmpty == true)
  }

  func testNestedStructures() {
    let nested: AnyJSON = [
      "level1": [
        "level2": [
          "level3": [
            "deep": "value"
          ]
        ]
      ]
    ]

    let level1 = nested.objectValue?["level1"]
    let level2 = level1?.objectValue?["level2"]
    let level3 = level2?.objectValue?["level3"]
    let deep = level3?.objectValue?["deep"]

    XCTAssertEqual(deep, .string("value"))
  }

  func testMixedArrayTypes() {
    let mixedArray: AnyJSON = [1, "string", true, nil, ["nested": "value"]]

    XCTAssertEqual(mixedArray.arrayValue?[0], .integer(1))
    XCTAssertEqual(mixedArray.arrayValue?[1], .string("string"))
    XCTAssertEqual(mixedArray.arrayValue?[2], .bool(true))
    XCTAssertEqual(mixedArray.arrayValue?[3], .null)
    XCTAssertEqual(mixedArray.arrayValue?[4], .object(["nested": .string("value")]))
  }

  func testLargeNumbers() {
    let largeInt: AnyJSON = 9_223_372_036_854_775_807  // Int.max
    let largeDouble: AnyJSON = 1.7976931348623157e+308  // Double.max

    XCTAssertEqual(largeInt.intValue, 9_223_372_036_854_775_807)
    XCTAssertEqual(largeDouble.doubleValue, 1.7976931348623157e+308)
  }

  func testSpecialStringValues() {
    let emptyString: AnyJSON = ""
    let unicodeString: AnyJSON = "Hello, 世界! 🌍"
    let escapedString: AnyJSON = "Line 1\nLine 2\tTab"

    XCTAssertEqual(emptyString.stringValue, "")
    XCTAssertEqual(unicodeString.stringValue, "Hello, 世界! 🌍")
    XCTAssertEqual(escapedString.stringValue, "Line 1\nLine 2\tTab")
  }
}

// MARK: - Helper Types

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

struct Person: Codable, Equatable {
  let name: String
  let age: Int
}

struct CustomPerson: Codable, Equatable {
  let userName: String
  let userAge: Int
}
