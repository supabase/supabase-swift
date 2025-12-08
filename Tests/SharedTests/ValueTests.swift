//
//  ValueTests.swift
//  SharedTests
//
//  Created by AI Assistant on 2025-01-27.
//

import Foundation
import Shared
import Testing

@Suite
struct ValueTests {

    // MARK: - Enum Cases Tests

    @Test
    func testNullCase() {
        let value = Value.null
        #expect(value == .null)
        #expect(value.isNull == true)
    }

    @Test
    func testBoolCase() {
        let trueValue = Value.bool(true)
        let falseValue = Value.bool(false)

        #expect(trueValue == .bool(true))
        #expect(falseValue == .bool(false))
        #expect(trueValue != falseValue)
    }

    @Test
    func testIntCase() {
        let value = Value.int(42)
        #expect(value == .int(42))
        #expect(value != .int(43))
    }

    @Test
    func testDoubleCase() {
        let value = Value.double(3.14)
        #expect(value == .double(3.14))
        #expect(value != .double(3.15))
    }

    @Test
    func testStringCase() {
        let value = Value.string("test")
        #expect(value == .string("test"))
        #expect(value != .string("different"))
    }

    @Test
    func testArrayCase() {
        let value = Value.array([.int(1), .string("test"), .bool(true)])
        #expect(value == .array([.int(1), .string("test"), .bool(true)]))
    }

    @Test
    func testObjectCase() {
        let value = Value.object(["key1": .string("value1"), "key2": .int(42)])
        #expect(value == .object(["key1": .string("value1"), "key2": .int(42)]))
    }

    // MARK: - Computed Properties Tests

    @Test
    func testIsNull() {
        #expect(Value.null.isNull == true)
        #expect(Value.bool(true).isNull == false)
        #expect(Value.int(42).isNull == false)
        #expect(Value.double(3.14).isNull == false)
        #expect(Value.string("test").isNull == false)
        #expect(Value.array([]).isNull == false)
        #expect(Value.object([:]).isNull == false)
    }

    @Test
    func testBoolValue() {
        #expect(Value.bool(true).boolValue == true)
        #expect(Value.bool(false).boolValue == false)
        #expect(Value.int(42).boolValue == nil)
        #expect(Value.double(3.14).boolValue == nil)
        #expect(Value.string("test").boolValue == nil)
        #expect(Value.null.boolValue == nil)
        #expect(Value.array([]).boolValue == nil)
        #expect(Value.object([:]).boolValue == nil)
    }

    @Test
    func testIntValue() {
        #expect(Value.int(42).intValue == 42)
        #expect(Value.int(-100).intValue == -100)
        #expect(Value.int(Int.max).intValue == Int.max)
        #expect(Value.bool(true).intValue == nil)
        #expect(Value.double(3.14).intValue == nil)
        #expect(Value.string("test").intValue == nil)
        #expect(Value.null.intValue == nil)
        #expect(Value.array([]).intValue == nil)
        #expect(Value.object([:]).intValue == nil)
    }

    @Test
    func testDoubleValue() {
        // Test double case
        #expect(Value.double(3.14).doubleValue == 3.14)
        #expect(Value.double(-100.5).doubleValue == -100.5)

        // Test int case (should convert to Double)
        #expect(Value.int(42).doubleValue == 42.0)
        #expect(Value.int(0).doubleValue == 0.0)
        #expect(Value.int(-100).doubleValue == -100.0)

        // Test other cases return nil
        #expect(Value.bool(true).doubleValue == nil)
        #expect(Value.string("test").doubleValue == nil)
        #expect(Value.null.doubleValue == nil)
        #expect(Value.array([]).doubleValue == nil)
        #expect(Value.object([:]).doubleValue == nil)
    }

    @Test
    func testStringValue() {
        #expect(Value.string("test").stringValue == "test")
        #expect(Value.string("").stringValue == "")
        #expect(Value.string("Hello, 世界! 🌍").stringValue == "Hello, 世界! 🌍")
        #expect(Value.bool(true).stringValue == nil)
        #expect(Value.int(42).stringValue == nil)
        #expect(Value.double(3.14).stringValue == nil)
        #expect(Value.null.stringValue == nil)
        #expect(Value.array([]).stringValue == nil)
        #expect(Value.object([:]).stringValue == nil)
    }

    @Test
    func testArrayValue() {
        let array: [Value] = [.int(1), .string("test"), .bool(true)]
        #expect(Value.array(array).arrayValue == array)
        #expect(Value.array([]).arrayValue == [])
        #expect(Value.bool(true).arrayValue == nil)
        #expect(Value.int(42).arrayValue == nil)
        #expect(Value.double(3.14).arrayValue == nil)
        #expect(Value.string("test").arrayValue == nil)
        #expect(Value.null.arrayValue == nil)
        #expect(Value.object([:]).arrayValue == nil)
    }

    @Test
    func testObjectValue() {
        let object: [String: Value] = ["key1": .string("value1"), "key2": .int(42)]
        #expect(Value.object(object).objectValue == object)
        #expect(Value.object([:]).objectValue == [:])
        #expect(Value.bool(true).objectValue == nil)
        #expect(Value.int(42).objectValue == nil)
        #expect(Value.double(3.14).objectValue == nil)
        #expect(Value.string("test").objectValue == nil)
        #expect(Value.null.objectValue == nil)
        #expect(Value.array([]).objectValue == nil)
    }

    // MARK: - Codable Tests

    @Test
    func testEncodeDecodeNull() throws {
        let value = Value.null
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(Value.self, from: data)
        #expect(decoded == value)
    }

    @Test
    func testEncodeDecodeBool() throws {
        let value = Value.bool(true)
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(Value.self, from: data)
        #expect(decoded == value)

        let falseValue = Value.bool(false)
        let falseData = try JSONEncoder().encode(falseValue)
        let decodedFalse = try JSONDecoder().decode(Value.self, from: falseData)
        #expect(decodedFalse == falseValue)
    }

    @Test
    func testEncodeDecodeInt() throws {
        let value = Value.int(42)
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(Value.self, from: data)
        #expect(decoded == value)

        // Test edge cases
        let maxInt = Value.int(Int.max)
        let maxData = try JSONEncoder().encode(maxInt)
        let decodedMax = try JSONDecoder().decode(Value.self, from: maxData)
        #expect(decodedMax == maxInt)

        let minInt = Value.int(Int.min)
        let minData = try JSONEncoder().encode(minInt)
        let decodedMin = try JSONDecoder().decode(Value.self, from: minData)
        #expect(decodedMin == minInt)
    }

    @Test
    func testEncodeDecodeDouble() throws {
        let value = Value.double(3.14)
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(Value.self, from: data)
        #expect(decoded == value)

        // Test edge cases
        let maxDouble = Value.double(Double.greatestFiniteMagnitude)
        let maxData = try JSONEncoder().encode(maxDouble)
        let decodedMax = try JSONDecoder().decode(Value.self, from: maxData)
        #expect(decodedMax == maxDouble)

        let minDouble = Value.double(-Double.greatestFiniteMagnitude)
        let minData = try JSONEncoder().encode(minDouble)
        let decodedMin = try JSONDecoder().decode(Value.self, from: minData)
        #expect(decodedMin == minDouble)
    }

    @Test
    func testEncodeDecodeString() throws {
        let value = Value.string("test")
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(Value.self, from: data)
        #expect(decoded == value)

        // Test empty string
        let emptyString = Value.string("")
        let emptyData = try JSONEncoder().encode(emptyString)
        let decodedEmpty = try JSONDecoder().decode(Value.self, from: emptyData)
        #expect(decodedEmpty == emptyString)

        // Test unicode
        let unicodeString = Value.string("Hello, 世界! 🌍")
        let unicodeData = try JSONEncoder().encode(unicodeString)
        let decodedUnicode = try JSONDecoder().decode(Value.self, from: unicodeData)
        #expect(decodedUnicode == unicodeString)
    }

    @Test
    func testEncodeDecodeArray() throws {
        let value = Value.array([.int(1), .string("test"), .bool(true), .null])
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(Value.self, from: data)
        #expect(decoded == value)

        // Test empty array
        let emptyArray = Value.array([])
        let emptyData = try JSONEncoder().encode(emptyArray)
        let decodedEmpty = try JSONDecoder().decode(Value.self, from: emptyData)
        #expect(decodedEmpty == emptyArray)

        // Test nested arrays
        let nestedArray = Value.array([.array([.int(1), .int(2)])])
        let nestedData = try JSONEncoder().encode(nestedArray)
        let decodedNested = try JSONDecoder().decode(Value.self, from: nestedData)
        #expect(decodedNested == nestedArray)
    }

    @Test
    func testEncodeDecodeObject() throws {
        let value = Value.object([
            "key1": .string("value1"),
            "key2": .int(42),
            "key3": .bool(true),
            "key4": .null,
        ])
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(Value.self, from: data)
        #expect(decoded == value)

        // Test empty object
        let emptyObject = Value.object([:])
        let emptyData = try JSONEncoder().encode(emptyObject)
        let decodedEmpty = try JSONDecoder().decode(Value.self, from: emptyData)
        #expect(decodedEmpty == emptyObject)

        // Test nested objects
        let nestedObject = Value.object([
            "nested": .object(["key": .string("value")])
        ])
        let nestedData = try JSONEncoder().encode(nestedObject)
        let decodedNested = try JSONDecoder().decode(Value.self, from: nestedData)
        #expect(decodedNested == nestedObject)
    }

    @Test
    func testEncodeDecodeComplexStructure() throws {
        let complexValue = Value.object([
            "string": .string("test"),
            "number": .int(42),
            "double": .double(3.14),
            "bool": .bool(true),
            "null": .null,
            "array": .array([.int(1), .string("two"), .bool(false)]),
            "object": .object([
                "nested": .string("value"),
                "nestedArray": .array([.int(1), .int(2), .int(3)]),
            ]),
        ])

        let data = try JSONEncoder().encode(complexValue)
        let decoded = try JSONDecoder().decode(Value.self, from: data)
        #expect(decoded == complexValue)
    }

    // MARK: - Init from Codable Tests

    @Test
    func testInitFromValue() throws {
        let originalValue = Value.string("test")
        let newValue = try Value(originalValue)
        #expect(newValue == originalValue)
    }

    @Test
    func testInitFromBool() throws {
        let value = try Value(true as Bool)
        #expect(value == .bool(true))

        let falseValue = try Value(false as Bool)
        #expect(falseValue == .bool(false))
    }

    @Test
    func testInitFromInt() throws {
        let value = try Value(42 as Int)
        #expect(value == .int(42))

        let maxValue = try Value(Int.max as Int)
        #expect(maxValue == .int(Int.max))
    }

    @Test
    func testInitFromDouble() throws {
        let value = try Value(3.14 as Double)
        #expect(value == .double(3.14))
    }

    @Test
    func testInitFromString() throws {
        let value = try Value("test" as String)
        #expect(value == .string("test"))
    }

    @Test
    func testInitFromArray() throws {
        let value = try Value([1, 2, 3])
        #expect(value == .array([.int(1), .int(2), .int(3)]))
    }

    @Test
    func testInitFromDictionary() throws {
        struct TestDict: Codable {
            let key1: String
            let key2: Int
        }

        let dict = TestDict(key1: "value1", key2: 42)
        let value = try Value(dict)
        let expected = Value.object([
            "key1": .string("value1"),
            "key2": .int(42),
        ])
        #expect(value == expected)
    }

    @Test
    func testInitFromCodableStruct() throws {
        struct TestStruct: Codable {
            let name: String
            let age: Int
            let active: Bool
        }

        let testStruct = TestStruct(name: "John", age: 30, active: true)
        let value = try Value(testStruct)

        let decoded = try JSONDecoder().decode(
            TestStruct.self, from: try JSONEncoder().encode(value))
        #expect(decoded.name == "John")
        #expect(decoded.age == 30)
        #expect(decoded.active == true)
    }

    // MARK: - ExpressibleByLiteral Tests

    @Test
    func testExpressibleByStringLiteral() {
        let value: Value = "test string"
        #expect(value == .string("test string"))
    }

    @Test
    func testExpressibleByIntegerLiteral() {
        let value: Value = 42
        #expect(value == .int(42))
    }

    @Test
    func testExpressibleByFloatLiteral() {
        let value: Value = 3.14
        #expect(value == .double(3.14))
    }

    @Test
    func testExpressibleByBooleanLiteral() {
        let trueValue: Value = true
        #expect(trueValue == .bool(true))

        let falseValue: Value = false
        #expect(falseValue == .bool(false))
    }

    @Test
    func testExpressibleByArrayLiteral() {
        let value: Value = [.int(1), .string("test"), .bool(true), .null]
        #expect(value == .array([.int(1), .string("test"), .bool(true), .null]))
    }

    @Test
    func testExpressibleByDictionaryLiteral() {
        let value: Value = [
            "key1": .string("value1"),
            "key2": .int(42),
            "key3": .bool(true),
        ]
        let expected = Value.object([
            "key1": .string("value1"),
            "key2": .int(42),
            "key3": .bool(true),
        ])
        #expect(value == expected)
    }

    @Test
    func testExpressibleByStringInterpolation() {
        let name = "John"
        let age = 30
        let value: Value = "Name: \(name), Age: \(age)"
        #expect(value == .string("Name: John, Age: 30"))
    }

    // MARK: - CustomStringConvertible Tests

    @Test
    func testDescription() {
        #expect(Value.null.description == "")
        #expect(Value.bool(true).description == "true")
        #expect(Value.bool(false).description == "false")
        #expect(Value.int(42).description == "42")
        #expect(Value.double(3.14).description == "3.14")
        #expect(Value.string("test").description == "test")

        // Test array description
        let array = Value.array([.int(1), .string("test")])
        let arrayDescription = array.description
        #expect(arrayDescription.contains("1") || arrayDescription.contains("test"))

        // Test object description
        let object = Value.object(["key": .string("value")])
        let objectDescription = object.description
        #expect(objectDescription.contains("key") || objectDescription.contains("value"))
    }

    // MARK: - Hashable Tests

    @Test
    func testEquality() {
        // Test same values
        #expect(Value.null == Value.null)
        #expect(Value.string("test") == Value.string("test"))
        #expect(Value.int(42) == Value.int(42))
        #expect(Value.double(3.14) == Value.double(3.14))
        #expect(Value.bool(true) == Value.bool(true))
        #expect(Value.bool(false) == Value.bool(false))

        // Test different values
        #expect(Value.string("test") != Value.string("different"))
        #expect(Value.int(42) != Value.int(43))
        #expect(Value.double(3.14) != Value.double(3.15))
        #expect(Value.bool(true) != Value.bool(false))

        // Test different types
        #expect(Value.string("42") != Value.int(42))
        #expect(Value.int(42) != Value.double(42.0))
        #expect(Value.null != Value.string(""))

        // Test arrays
        let array1 = Value.array([.int(1), .int(2)])
        let array2 = Value.array([.int(1), .int(2)])
        let array3 = Value.array([.int(1), .int(3)])
        #expect(array1 == array2)
        #expect(array1 != array3)

        // Test objects
        let object1 = Value.object(["key": .string("value")])
        let object2 = Value.object(["key": .string("value")])
        let object3 = Value.object(["key": .string("different")])
        #expect(object1 == object2)
        #expect(object1 != object3)
    }

    @Test
    func testHashable() {
        var set: Set<Value> = []
        set.insert(.null)
        set.insert(.string("test"))
        set.insert(.int(42))
        set.insert(.double(3.14))
        set.insert(.bool(true))
        set.insert(.object(["key": .string("value")]))
        set.insert(.array([.int(1), .int(2)]))

        #expect(set.count == 7)
        #expect(set.contains(.null))
        #expect(set.contains(.string("test")))
        #expect(set.contains(.int(42)))
        #expect(set.contains(.double(3.14)))
        #expect(set.contains(.bool(true)))
        #expect(set.contains(.object(["key": .string("value")])))
        #expect(set.contains(.array([.int(1), .int(2)])))
    }

    // MARK: - toValueObject Extension Tests

    @Test
    func testToValueObject() throws {
        struct TestStruct: Codable {
            let name: String
            let age: Int
            let active: Bool
        }

        let testStruct = TestStruct(name: "John", age: 30, active: true)
        let valueObject = try testStruct.toValueObject()

        #expect(valueObject["name"] == .string("John"))
        #expect(valueObject["age"] == .int(30))
        #expect(valueObject["active"] == .bool(true))
    }

    @Test
    func testToValueObjectWithCustomEncoder() throws {
        struct TestStruct: Codable {
            let userName: String
            let userAge: Int
        }

        let testStruct = TestStruct(userName: "John", userAge: 30)
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase

        let valueObject = try testStruct.toValueObject(encoder: encoder)

        #expect(valueObject["user_name"] == .string("John"))
        #expect(valueObject["user_age"] == .int(30))
    }

    // MARK: - Edge Cases Tests

    @Test
    func testEmptyValues() {
        let emptyString = Value.string("")
        #expect(emptyString.stringValue == "")

        let emptyArray = Value.array([])
        #expect(emptyArray.arrayValue == [])

        let emptyObject = Value.object([:])
        #expect(emptyObject.objectValue == [:])
    }

    @Test
    func testNestedStructures() {
        let nested = Value.object([
            "level1": .object([
                "level2": .object([
                    "level3": .object([
                        "deep": .string("value")
                    ])
                ])
            ])
        ])

        let level1 = nested.objectValue?["level1"]
        let level2 = level1?.objectValue?["level2"]
        let level3 = level2?.objectValue?["level3"]
        let deep = level3?.objectValue?["deep"]

        #expect(deep == .string("value"))
    }

    @Test
    func testMixedArrayTypes() {
        let mixedArray = Value.array([
            .int(1),
            .string("string"),
            .bool(true),
            .null,
            .object(["nested": .string("value")]),
        ])

        #expect(mixedArray.arrayValue?[0] == .int(1))
        #expect(mixedArray.arrayValue?[1] == .string("string"))
        #expect(mixedArray.arrayValue?[2] == .bool(true))
        #expect(mixedArray.arrayValue?[3] == .null)
        #expect(mixedArray.arrayValue?[4] == .object(["nested": .string("value")]))
    }

    @Test
    func testLargeNumbers() {
        let largeInt = Value.int(Int.max)
        #expect(largeInt.intValue == Int.max)

        let largeDouble = Value.double(Double.greatestFiniteMagnitude)
        #expect(largeDouble.doubleValue == Double.greatestFiniteMagnitude)
    }

    @Test
    func testSpecialStringValues() {
        let emptyString = Value.string("")
        #expect(emptyString.stringValue == "")

        let unicodeString = Value.string("Hello, 世界! 🌍")
        #expect(unicodeString.stringValue == "Hello, 世界! 🌍")

        let escapedString = Value.string("Line 1\nLine 2\tTab")
        #expect(escapedString.stringValue == "Line 1\nLine 2\tTab")
    }

    @Test
    func testDoubleValueFromInt() {
        // Test that int values can be converted to double
        #expect(Value.int(0).doubleValue == 0.0)
        #expect(Value.int(42).doubleValue == 42.0)
        #expect(Value.int(-100).doubleValue == -100.0)
        #expect(Value.int(Int.max).doubleValue == Double(Int.max))
        #expect(Value.int(Int.min).doubleValue == Double(Int.min))
    }

    @Test
    func testRoundTripEncoding() throws {
        let original = Value.object([
            "string": .string("test"),
            "number": .int(42),
            "double": .double(3.14),
            "bool": .bool(true),
            "null": .null,
            "array": .array([.int(1), .string("two")]),
            "object": .object(["nested": .string("value")]),
        ])

        // Encode to JSON
        let jsonData = try JSONEncoder().encode(original)

        // Decode back
        let decoded = try JSONDecoder().decode(Value.self, from: jsonData)

        // Should be equal
        #expect(decoded == original)

        // Encode again to ensure consistency
        let jsonData2 = try JSONEncoder().encode(decoded)
        let decoded2 = try JSONDecoder().decode(Value.self, from: jsonData2)
        #expect(decoded2 == original)
    }
}
