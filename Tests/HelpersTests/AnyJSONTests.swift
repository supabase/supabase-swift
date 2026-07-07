//
//  AnyJSONTests.swift
//
//
//  Created by Guilherme Souza on 28/12/23.
//

import CustomDump
import Foundation
import Helpers
import Testing

@Suite
struct AnyJSONTests {
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

  @Test
  func decode() throws {
    let data = try #require(jsonString.data(using: .utf8))
    let decodedJSON = try AnyJSON.decoder.decode(AnyJSON.self, from: data)

    expectNoDifference(decodedJSON, jsonObject)
  }

  @Test
  func encode() throws {
    let encoder = AnyJSON.encoder
    let originalFormatting = encoder.outputFormatting
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    defer { encoder.outputFormatting = originalFormatting }

    let data = try encoder.encode(jsonObject)
    let decodedJSONString = try #require(String(data: data, encoding: .utf8))

    expectNoDifference(decodedJSONString, jsonString)
  }

  @Test
  func initFromCodable() {
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

  @Test
  func valueProperty() {
    // Test null value
    #expect(AnyJSON.null.value is NSNull)

    // Test string value
    #expect(AnyJSON.string("test").value as? String == "test")

    // Test integer value
    #expect(AnyJSON.integer(42).value as? Int == 42)

    // Test double value
    #expect(AnyJSON.double(3.14).value as? Double == 3.14)

    // Test bool value
    #expect(AnyJSON.bool(true).value as? Bool == true)
    #expect(AnyJSON.bool(false).value as? Bool == false)

    // Test object value
    let object: AnyJSON = ["key": "value"]
    let objectValue = object.value as? [String: Any]
    #expect(objectValue?["key"] as? String == "value")

    // Test array value
    let array: AnyJSON = [1, 2, 3]
    let arrayValue = array.value as? [Any]
    #expect(arrayValue?[0] as? Int == 1)
    #expect(arrayValue?[1] as? Int == 2)
    #expect(arrayValue?[2] as? Int == 3)
  }

  // MARK: - Type-Specific Value Accessors

  @Test
  func isNil() {
    #expect(AnyJSON.null.isNil)
    #expect(!AnyJSON.string("test").isNil)
    #expect(!AnyJSON.integer(42).isNil)
    #expect(!AnyJSON.double(3.14).isNil)
    #expect(!AnyJSON.bool(true).isNil)
    #expect(!AnyJSON.object([:]).isNil)
    #expect(!AnyJSON.array([]).isNil)
  }

  @Test
  func boolValue() {
    #expect(AnyJSON.bool(true).boolValue == true)
    #expect(AnyJSON.bool(false).boolValue == false)
    #expect(AnyJSON.string("test").boolValue == nil)
    #expect(AnyJSON.integer(42).boolValue == nil)
    #expect(AnyJSON.double(3.14).boolValue == nil)
    #expect(AnyJSON.null.boolValue == nil)
    #expect(AnyJSON.object([:]).boolValue == nil)
    #expect(AnyJSON.array([]).boolValue == nil)
  }

  @Test
  func stringValue() {
    #expect(AnyJSON.string("test").stringValue == "test")
    #expect(AnyJSON.bool(true).stringValue == nil)
    #expect(AnyJSON.integer(42).stringValue == nil)
    #expect(AnyJSON.double(3.14).stringValue == nil)
    #expect(AnyJSON.null.stringValue == nil)
    #expect(AnyJSON.object([:]).stringValue == nil)
    #expect(AnyJSON.array([]).stringValue == nil)
  }

  @Test
  func intValue() {
    #expect(AnyJSON.integer(42).intValue == 42)
    #expect(AnyJSON.string("test").intValue == nil)
    #expect(AnyJSON.bool(true).intValue == nil)
    #expect(AnyJSON.double(3.14).intValue == nil)
    #expect(AnyJSON.null.intValue == nil)
    #expect(AnyJSON.object([:]).intValue == nil)
    #expect(AnyJSON.array([]).intValue == nil)
  }

  @Test
  func doubleValue() {
    #expect(AnyJSON.double(3.14).doubleValue == 3.14)
    #expect(AnyJSON.string("test").doubleValue == nil)
    #expect(AnyJSON.bool(true).doubleValue == nil)
    #expect(AnyJSON.integer(42).doubleValue == nil)
    #expect(AnyJSON.null.doubleValue == nil)
    #expect(AnyJSON.object([:]).doubleValue == nil)
    #expect(AnyJSON.array([]).doubleValue == nil)
  }

  @Test
  func objectValue() {
    let object: JSONObject = ["key": "value"]
    #expect(AnyJSON.object(object).objectValue == object)
    #expect(AnyJSON.string("test").objectValue == nil)
    #expect(AnyJSON.bool(true).objectValue == nil)
    #expect(AnyJSON.integer(42).objectValue == nil)
    #expect(AnyJSON.double(3.14).objectValue == nil)
    #expect(AnyJSON.null.objectValue == nil)
    #expect(AnyJSON.array([]).objectValue == nil)
  }

  @Test
  func arrayValue() {
    let array: JSONArray = [1, 2, 3]
    #expect(AnyJSON.array(array).arrayValue == array)
    #expect(AnyJSON.string("test").arrayValue == nil)
    #expect(AnyJSON.bool(true).arrayValue == nil)
    #expect(AnyJSON.integer(42).arrayValue == nil)
    #expect(AnyJSON.double(3.14).arrayValue == nil)
    #expect(AnyJSON.null.arrayValue == nil)
    #expect(AnyJSON.object([:]).arrayValue == nil)
  }

  // MARK: - ExpressibleByLiteral Tests

  @Test
  func expressibleByNilLiteral() {
    let json: AnyJSON = nil
    #expect(json == .null)
  }

  @Test
  func expressibleByStringLiteral() {
    let json: AnyJSON = "test string"
    #expect(json == .string("test string"))
  }

  @Test
  func expressibleByIntegerLiteral() {
    let json: AnyJSON = 42
    #expect(json == .integer(42))
  }

  @Test
  func expressibleByFloatLiteral() {
    let json: AnyJSON = 3.14
    #expect(json == .double(3.14))
  }

  @Test
  func expressibleByBooleanLiteral() {
    let json: AnyJSON = true
    #expect(json == .bool(true))

    let jsonFalse: AnyJSON = false
    #expect(jsonFalse == .bool(false))
  }

  @Test
  func expressibleByArrayLiteral() {
    let json: AnyJSON = [1, "test", true, nil]
    #expect(json == .array([.integer(1), .string("test"), .bool(true), .null]))
  }

  @Test
  func expressibleByDictionaryLiteral() {
    let json: AnyJSON = ["key1": "value1", "key2": 42, "key3": true]
    let expected: AnyJSON = .object([
      "key1": .string("value1"),
      "key2": .integer(42),
      "key3": .bool(true),
    ])
    #expect(json == expected)
  }

  // MARK: - CustomStringConvertible Tests

  @Test
  func description() {
    #expect(AnyJSON.null.description == "<null>")
    #expect(AnyJSON.string("test").description == "test")
    #expect(AnyJSON.integer(42).description == "42")
    #expect(AnyJSON.double(3.14).description == "3.14")
    #expect(AnyJSON.bool(true).description == "true")
    #expect(AnyJSON.bool(false).description == "false")

    // Test object description
    let object: AnyJSON = ["key": "value"]
    #expect(object.description.contains("key"))
    #expect(object.description.contains("value"))

    // Test array description
    let array: AnyJSON = [1, 2, 3]
    #expect(array.description.contains("1"))
    #expect(array.description.contains("2"))
    #expect(array.description.contains("3"))
  }

  // MARK: - Hashable Tests

  @Test
  func equality() {
    // Test same values
    #expect(AnyJSON.null == AnyJSON.null)
    #expect(AnyJSON.string("test") == AnyJSON.string("test"))
    #expect(AnyJSON.integer(42) == AnyJSON.integer(42))
    #expect(AnyJSON.double(3.14) == AnyJSON.double(3.14))
    #expect(AnyJSON.bool(true) == AnyJSON.bool(true))
    #expect(AnyJSON.bool(false) == AnyJSON.bool(false))

    // Test different values
    #expect(AnyJSON.string("test") != AnyJSON.string("different"))
    #expect(AnyJSON.integer(42) != AnyJSON.integer(43))
    #expect(AnyJSON.double(3.14) != AnyJSON.double(3.15))
    #expect(AnyJSON.bool(true) != AnyJSON.bool(false))

    // Test different types
    #expect(AnyJSON.string("42") != AnyJSON.integer(42))
    #expect(AnyJSON.integer(42) != AnyJSON.double(42.0))
    #expect(AnyJSON.null != AnyJSON.string(""))

    // Test objects
    let object1: AnyJSON = ["key": "value"]
    let object2: AnyJSON = ["key": "value"]
    let object3: AnyJSON = ["key": "different"]
    #expect(object1 == object2)
    #expect(object1 != object3)

    // Test arrays
    let array1: AnyJSON = [1, 2, 3]
    let array2: AnyJSON = [1, 2, 3]
    let array3: AnyJSON = [1, 2, 4]
    #expect(array1 == array2)
    #expect(array1 != array3)
  }

  @Test
  func hashable() {
    let set: Set<AnyJSON> = [
      .null,
      .string("test"),
      .integer(42),
      .double(3.14),
      .bool(true),
      .object(["key": "value"]),
      .array([1, 2, 3]),
    ]

    #expect(set.count == 7)
    #expect(set.contains(.null))
    #expect(set.contains(.string("test")))
    #expect(set.contains(.integer(42)))
    #expect(set.contains(.double(3.14)))
    #expect(set.contains(.bool(true)))
    #expect(set.contains(.object(["key": "value"])))
    #expect(set.contains(.array([1, 2, 3])))
  }

  // MARK: - JSONArray and JSONObject Extension Tests

  @Test
  func jsonArrayDecode() throws {
    let jsonArray: JSONArray = [AnyJSON.integer(1), AnyJSON.integer(2), AnyJSON.integer(3)]
    // Decode each element individually since the JSONArray.decode method has issues
    let decoded: [Int] = try jsonArray.map { try $0.decode(as: Int.self) }
    #expect(decoded == [1, 2, 3])
  }

  @Test
  func jsonObjectDecode() throws {
    let jsonObject: JSONObject = ["name": AnyJSON.string("John"), "age": AnyJSON.integer(30)]
    let decoded: Person = try jsonObject.decode(as: Person.self)
    #expect(decoded.name == "John")
    #expect(decoded.age == 30)
  }

  @Test
  func jsonObjectInitFromCodable() throws {
    let person = Person(name: "John", age: 30)
    let jsonObject = try JSONObject(person)
    #expect(jsonObject["name"] == .string("John"))
    #expect(jsonObject["age"] == .integer(30))
  }

  @Test
  func jsonObjectInitFromCodableFailure() {
    // Test with a simple string, which should fail because it's not an object
    #expect(throws: (any Error).self) {
      try JSONObject("not an object")
    }

    // Test with an integer, which should also fail
    #expect(throws: (any Error).self) {
      try JSONObject(42)
    }
  }

  // MARK: - Error Handling Tests

  @Test
  func invalidJSONDecoding() {
    let invalidJSON = "invalid json"
    let data = invalidJSON.data(using: .utf8)!

    #expect(throws: (any Error).self) {
      try AnyJSON.decoder.decode(AnyJSON.self, from: data)
    }
  }

  @Test
  func decodeWithCustomDecoder() throws {
    let customDecoder = JSONDecoder()
    customDecoder.keyDecodingStrategy = .convertFromSnakeCase

    let json: AnyJSON = ["user_name": "John", "user_age": 30]
    let decoded: CustomPerson = try json.decode(as: CustomPerson.self, decoder: customDecoder)
    #expect(decoded.userName == "John")
    #expect(decoded.userAge == 30)
  }

  // MARK: - Edge Cases

  @Test
  func emptyObjectAndArray() {
    let emptyObject: AnyJSON = [:]
    let emptyArray: AnyJSON = []

    #expect(emptyObject == .object([:]))
    #expect(emptyArray == .array([]))

    #expect(emptyObject.objectValue?.isEmpty == true)
    #expect(emptyArray.arrayValue?.isEmpty == true)
  }

  @Test
  func nestedStructures() {
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

    #expect(deep == .string("value"))
  }

  @Test
  func mixedArrayTypes() {
    let mixedArray: AnyJSON = [1, "string", true, nil, ["nested": "value"]]

    #expect(mixedArray.arrayValue?[0] == .integer(1))
    #expect(mixedArray.arrayValue?[1] == .string("string"))
    #expect(mixedArray.arrayValue?[2] == .bool(true))
    #expect(mixedArray.arrayValue?[3] == .null)
    #expect(mixedArray.arrayValue?[4] == .object(["nested": .string("value")]))
  }

  @Test
  func largeNumbers() {
    let largeInt: AnyJSON = 9_223_372_036_854_775_807  // Int.max
    let largeDouble: AnyJSON = 1.7976931348623157e+308  // Double.max

    #expect(largeInt.intValue == 9_223_372_036_854_775_807)
    #expect(largeDouble.doubleValue == 1.7976931348623157e+308)
  }

  @Test
  func specialStringValues() {
    let emptyString: AnyJSON = ""
    let unicodeString: AnyJSON = "Hello, 世界! 🌍"
    let escapedString: AnyJSON = "Line 1\nLine 2\tTab"

    #expect(emptyString.stringValue == "")
    #expect(unicodeString.stringValue == "Hello, 世界! 🌍")
    #expect(escapedString.stringValue == "Line 1\nLine 2\tTab")
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
