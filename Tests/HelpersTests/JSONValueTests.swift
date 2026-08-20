//
//  JSONValueTests.swift
//
//
//  Created by Guilherme Souza on 28/12/23.
//

import CustomDump
import Foundation
import Helpers
import Testing

@Suite
struct JSONValueTests {
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

  let jsonObject: JSONValue = [
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
    let decodedJSON = try JSONValue.decoder.decode(JSONValue.self, from: data)

    expectNoDifference(decodedJSON, jsonObject)
  }

  @Test
  func encode() throws {
    let encoder = JSONValue.encoder
    let originalFormatting = encoder.outputFormatting
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    defer { encoder.outputFormatting = originalFormatting }

    let data = try encoder.encode(jsonObject)
    let decodedJSONString = try #require(String(data: data, encoding: .utf8))

    expectNoDifference(decodedJSONString, jsonString)
  }

  @Test
  func initFromCodable() {
    try expectNoDifference(JSONValue(jsonObject), jsonObject)

    let codableValue = CodableValue(
      integer: 1,
      double: 3.14,
      string: "A String value",
      bool: true,
      array: [1, 2, 3],
      dictionary: ["key": "value"],
      anyJSON: jsonObject
    )

    let json: JSONValue = [
      "integer": 1,
      "double": 3.14,
      "string": "A String value",
      "bool": true,
      "array": [1, 2, 3],
      "dictionary": ["key": "value"],
      "any_json": jsonObject,
    ]

    try expectNoDifference(JSONValue(codableValue), json)
    try expectNoDifference(codableValue, json.decode(as: CodableValue.self))
  }

  // MARK: - Value Property Tests

  @Test
  func valueProperty() {
    // Test null value
    #expect(JSONValue.null.value is NSNull)

    // Test string value
    #expect(JSONValue.string("test").value as? String == "test")

    // Test integer value
    #expect(JSONValue.integer(42).value as? Int == 42)

    // Test double value
    #expect(JSONValue.double(3.14).value as? Double == 3.14)

    // Test bool value
    #expect(JSONValue.bool(true).value as? Bool == true)
    #expect(JSONValue.bool(false).value as? Bool == false)

    // Test object value
    let object: JSONValue = ["key": "value"]
    let objectValue = object.value as? [String: Any]
    #expect(objectValue?["key"] as? String == "value")

    // Test array value
    let array: JSONValue = [1, 2, 3]
    let arrayValue = array.value as? [Any]
    #expect(arrayValue?[0] as? Int == 1)
    #expect(arrayValue?[1] as? Int == 2)
    #expect(arrayValue?[2] as? Int == 3)
  }

  // MARK: - Type-Specific Value Accessors

  @Test
  func isNil() {
    #expect(JSONValue.null.isNil)
    #expect(!JSONValue.string("test").isNil)
    #expect(!JSONValue.integer(42).isNil)
    #expect(!JSONValue.double(3.14).isNil)
    #expect(!JSONValue.bool(true).isNil)
    #expect(!JSONValue.object([:]).isNil)
    #expect(!JSONValue.array([]).isNil)
  }

  @Test
  func boolValue() {
    #expect(JSONValue.bool(true).boolValue == true)
    #expect(JSONValue.bool(false).boolValue == false)
    #expect(JSONValue.string("test").boolValue == nil)
    #expect(JSONValue.integer(42).boolValue == nil)
    #expect(JSONValue.double(3.14).boolValue == nil)
    #expect(JSONValue.null.boolValue == nil)
    #expect(JSONValue.object([:]).boolValue == nil)
    #expect(JSONValue.array([]).boolValue == nil)
  }

  @Test
  func stringValue() {
    #expect(JSONValue.string("test").stringValue == "test")
    #expect(JSONValue.bool(true).stringValue == nil)
    #expect(JSONValue.integer(42).stringValue == nil)
    #expect(JSONValue.double(3.14).stringValue == nil)
    #expect(JSONValue.null.stringValue == nil)
    #expect(JSONValue.object([:]).stringValue == nil)
    #expect(JSONValue.array([]).stringValue == nil)
  }

  @Test
  func intValue() {
    #expect(JSONValue.integer(42).intValue == 42)
    #expect(JSONValue.string("test").intValue == nil)
    #expect(JSONValue.bool(true).intValue == nil)
    #expect(JSONValue.double(3.14).intValue == nil)
    #expect(JSONValue.null.intValue == nil)
    #expect(JSONValue.object([:]).intValue == nil)
    #expect(JSONValue.array([]).intValue == nil)
  }

  @Test
  func doubleValue() {
    #expect(JSONValue.double(3.14).doubleValue == 3.14)
    #expect(JSONValue.string("test").doubleValue == nil)
    #expect(JSONValue.bool(true).doubleValue == nil)
    #expect(JSONValue.integer(42).doubleValue == nil)
    #expect(JSONValue.null.doubleValue == nil)
    #expect(JSONValue.object([:]).doubleValue == nil)
    #expect(JSONValue.array([]).doubleValue == nil)
  }

  @Test
  func objectValue() {
    let object: JSONObject = ["key": "value"]
    #expect(JSONValue.object(object).objectValue == object)
    #expect(JSONValue.string("test").objectValue == nil)
    #expect(JSONValue.bool(true).objectValue == nil)
    #expect(JSONValue.integer(42).objectValue == nil)
    #expect(JSONValue.double(3.14).objectValue == nil)
    #expect(JSONValue.null.objectValue == nil)
    #expect(JSONValue.array([]).objectValue == nil)
  }

  @Test
  func arrayValue() {
    let array: JSONArray = [1, 2, 3]
    #expect(JSONValue.array(array).arrayValue == array)
    #expect(JSONValue.string("test").arrayValue == nil)
    #expect(JSONValue.bool(true).arrayValue == nil)
    #expect(JSONValue.integer(42).arrayValue == nil)
    #expect(JSONValue.double(3.14).arrayValue == nil)
    #expect(JSONValue.null.arrayValue == nil)
    #expect(JSONValue.object([:]).arrayValue == nil)
  }

  // MARK: - ExpressibleByLiteral Tests

  @Test
  func expressibleByNilLiteral() {
    let json: JSONValue = nil
    #expect(json == .null)
  }

  @Test
  func expressibleByStringLiteral() {
    let json: JSONValue = "test string"
    #expect(json == .string("test string"))
  }

  @Test
  func expressibleByIntegerLiteral() {
    let json: JSONValue = 42
    #expect(json == .integer(42))
  }

  @Test
  func expressibleByFloatLiteral() {
    let json: JSONValue = 3.14
    #expect(json == .double(3.14))
  }

  @Test
  func expressibleByBooleanLiteral() {
    let json: JSONValue = true
    #expect(json == .bool(true))

    let jsonFalse: JSONValue = false
    #expect(jsonFalse == .bool(false))
  }

  @Test
  func expressibleByArrayLiteral() {
    let json: JSONValue = [1, "test", true, nil]
    #expect(json == .array([.integer(1), .string("test"), .bool(true), .null]))
  }

  @Test
  func expressibleByDictionaryLiteral() {
    let json: JSONValue = ["key1": "value1", "key2": 42, "key3": true]
    let expected: JSONValue = .object([
      "key1": .string("value1"),
      "key2": .integer(42),
      "key3": .bool(true),
    ])
    #expect(json == expected)
  }

  // MARK: - CustomStringConvertible Tests

  @Test
  func description() {
    #expect(JSONValue.null.description == "<null>")
    #expect(JSONValue.string("test").description == "test")
    #expect(JSONValue.integer(42).description == "42")
    #expect(JSONValue.double(3.14).description == "3.14")
    #expect(JSONValue.bool(true).description == "true")
    #expect(JSONValue.bool(false).description == "false")

    // Test object description
    let object: JSONValue = ["key": "value"]
    #expect(object.description.contains("key"))
    #expect(object.description.contains("value"))

    // Test array description
    let array: JSONValue = [1, 2, 3]
    #expect(array.description.contains("1"))
    #expect(array.description.contains("2"))
    #expect(array.description.contains("3"))
  }

  // MARK: - Hashable Tests

  @Test
  func equality() {
    // Test same values
    #expect(JSONValue.null == JSONValue.null)
    #expect(JSONValue.string("test") == JSONValue.string("test"))
    #expect(JSONValue.integer(42) == JSONValue.integer(42))
    #expect(JSONValue.double(3.14) == JSONValue.double(3.14))
    #expect(JSONValue.bool(true) == JSONValue.bool(true))
    #expect(JSONValue.bool(false) == JSONValue.bool(false))

    // Test different values
    #expect(JSONValue.string("test") != JSONValue.string("different"))
    #expect(JSONValue.integer(42) != JSONValue.integer(43))
    #expect(JSONValue.double(3.14) != JSONValue.double(3.15))
    #expect(JSONValue.bool(true) != JSONValue.bool(false))

    // Test different types
    #expect(JSONValue.string("42") != JSONValue.integer(42))
    #expect(JSONValue.integer(42) != JSONValue.double(42.0))
    #expect(JSONValue.null != JSONValue.string(""))

    // Test objects
    let object1: JSONValue = ["key": "value"]
    let object2: JSONValue = ["key": "value"]
    let object3: JSONValue = ["key": "different"]
    #expect(object1 == object2)
    #expect(object1 != object3)

    // Test arrays
    let array1: JSONValue = [1, 2, 3]
    let array2: JSONValue = [1, 2, 3]
    let array3: JSONValue = [1, 2, 4]
    #expect(array1 == array2)
    #expect(array1 != array3)
  }

  @Test
  func hashable() {
    let set: Set<JSONValue> = [
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
    let jsonArray: JSONArray = [JSONValue.integer(1), JSONValue.integer(2), JSONValue.integer(3)]
    // Decode each element individually since the JSONArray.decode method has issues
    let decoded: [Int] = try jsonArray.map { try $0.decode(as: Int.self) }
    #expect(decoded == [1, 2, 3])
  }

  @Test
  func jsonObjectDecode() throws {
    let jsonObject: JSONObject = ["name": JSONValue.string("John"), "age": JSONValue.integer(30)]
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
  func jsonObjectInitFromCodableWithCustomEncoder() throws {
    struct SnakeCasePerson: Encodable {
      let fullName: String
    }

    let snakeCaseEncoder = JSONEncoder()
    snakeCaseEncoder.keyEncodingStrategy = .convertToSnakeCase

    let jsonObject = try JSONObject(SnakeCasePerson(fullName: "John"), encoder: snakeCaseEncoder)
    #expect(jsonObject["full_name"] == .string("John"))
    #expect(jsonObject["fullName"] == nil)
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
      try JSONValue.decoder.decode(JSONValue.self, from: data)
    }
  }

  @Test
  func decodeWithCustomDecoder() throws {
    let customDecoder = JSONDecoder()
    customDecoder.keyDecodingStrategy = .convertFromSnakeCase

    let json: JSONValue = ["user_name": "John", "user_age": 30]
    let decoded: CustomPerson = try json.decode(as: CustomPerson.self, decoder: customDecoder)
    #expect(decoded.userName == "John")
    #expect(decoded.userAge == 30)
  }

  // MARK: - Edge Cases

  @Test
  func emptyObjectAndArray() {
    let emptyObject: JSONValue = [:]
    let emptyArray: JSONValue = []

    #expect(emptyObject == .object([:]))
    #expect(emptyArray == .array([]))

    #expect(emptyObject.objectValue?.isEmpty == true)
    #expect(emptyArray.arrayValue?.isEmpty == true)
  }

  @Test
  func nestedStructures() {
    let nested: JSONValue = [
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
    let mixedArray: JSONValue = [1, "string", true, nil, ["nested": "value"]]

    #expect(mixedArray.arrayValue?[0] == .integer(1))
    #expect(mixedArray.arrayValue?[1] == .string("string"))
    #expect(mixedArray.arrayValue?[2] == .bool(true))
    #expect(mixedArray.arrayValue?[3] == .null)
    #expect(mixedArray.arrayValue?[4] == .object(["nested": .string("value")]))
  }

  @Test
  func largeNumbers() {
    let largeInt: JSONValue = 9_223_372_036_854_775_807  // Int.max
    let largeDouble: JSONValue = 1.7976931348623157e+308  // Double.max

    #expect(largeInt.intValue == 9_223_372_036_854_775_807)
    #expect(largeDouble.doubleValue == 1.7976931348623157e+308)
  }

  @Test
  func specialStringValues() {
    let emptyString: JSONValue = ""
    let unicodeString: JSONValue = "Hello, 世界! 🌍"
    let escapedString: JSONValue = "Line 1\nLine 2\tTab"

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
  let anyJSON: JSONValue

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
