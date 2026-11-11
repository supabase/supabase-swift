import Foundation
@testable import Helpers
import Testing

@Suite
struct JSONNumberTests {
  private func roundTrip(_ json: String) throws -> String {
    let value = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
    return String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
  }

  @Test(arguments: [
    "9223372036854775809",
    "18446744073709551615",
    "-9223372036854775808",
    "12345678901234567.89",
    "-12345678901234567.89",
    "9007199254740993.5",
    "0.1",
    "3.14",
    "42",
    "0",
  ])
  func decodingAndEncodingKeepsEveryDigit(json: String) throws {
    #expect(try roundTrip(json) == json)
    #expect(try roundTrip("[\(json)]") == "[\(json)]")
  }

  @Test func decodingNeverCutsOffAFraction() throws {
    let value = try JSONDecoder().decode(JSONValue.self, from: Data("12345678901234567.89".utf8))
    #expect(value == .number(JSONNumber("12345678901234567.89")!))
    #expect(value.intValue == nil)
  }

  @Test func decodingANumberOutsideDecimalRangeFallsBackToDouble() throws {
    let value = try JSONDecoder().decode(JSONValue.self, from: Data("1e300".utf8))
    #expect(value.doubleValue == 1e300)
  }

  /// Before iOS 17 and macOS 14, `JSONDecoder` builds a `Decimal` from a parsed `Double`.
  @Test(arguments: [3.133, 0.1, 42, -2.5e-30])
  func aDecimalBuiltFromADoubleDecodesAsTheShortestDoubleText(double: Double) {
    let number = JSONNumber.decoded(
      decimal: Decimal(double), double: double, decimalIsBuiltFromDouble: true)
    #expect(number == JSONNumber(double))
  }

  @Test func anExactDecimalDecodesWithEveryDigit() {
    let decimal = Decimal(string: "-9223372036854775808")!
    let number = JSONNumber.decoded(
      decimal: decimal, double: -9223372036854775808, decimalIsBuiltFromDouble: false)
    #expect(number?.description == "-9223372036854775808")
  }

  @Test func encodableRoundTripKeepsDecimalAndUInt64() throws {
    struct Row: Codable, Equatable {
      var amount: Decimal
      var counter: UInt64
    }
    let row = Row(amount: Decimal(string: "12345678901234567.89")!, counter: .max)

    let value = try JSONValue(row)

    #expect(value.objectValue?["amount"]?.numberValue?.description == "12345678901234567.89")
    #expect(value.objectValue?["counter"]?.numberValue?.description == "18446744073709551615")
    #expect(try value.decode(as: Row.self) == row)
  }

  @Test(arguments: [
    ("1.50", "1.5"),
    ("1.0", "1"),
    ("1e2", "100"),
    ("1E+2", "100"),
    ("1e-2", "0.01"),
    ("-0", "0"),
    ("-0.0", "0"),
    ("0.000", "0"),
    ("1000", "1000"),
    ("1e40", "1e40"),
    ("-1.5e-30", "-1.5e-30"),
    ("12.5e-1", "1.25"),
  ])
  func descriptionIsCanonical(text: String, canonical: String) {
    #expect(JSONNumber(text)?.description == canonical)
  }

  @Test(arguments: [
    "", "01", "1.", ".1", "+1", "abc", "1e", "1e+", "NaN", "Infinity", " 1", "1 ", "--1", "0x10",
  ])
  func stringInitRejectsTextOutsideTheJSONNumberGrammar(text: String) {
    #expect(JSONNumber(text) == nil)
  }

  @Test(arguments: [
    "1e99999999999999999999", "1e2147483648", "1e-2147483648", "10e2147483647",
  ])
  func stringInitRejectsAPowerOfTenOutsideInt32(text: String) {
    #expect(JSONNumber(text) == nil)
  }

  @Test func decodingANonNumberThrows() {
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(JSONNumber.self, from: Data(#""1""#.utf8))
    }
  }

  @Test func valueFallsBackToTheNearestDouble() {
    let value = JSONValue.number(JSONNumber("123456789012345678901234567890123456789012.5")!)
    #expect((value.value as? Double) == 123456789012345678901234567890123456789012.5)
  }

  @Test func numbersWithTheSameValueAreEqual() {
    let one: JSONValue = 1
    let onePointZero: JSONValue = 1.0
    #expect(one == onePointZero)
    #expect(one.hashValue == onePointZero.hashValue)
    #expect(JSONNumber("1e2") == JSONNumber(100))
    #expect(JSONNumber("1.5") != JSONNumber("1.50001"))
  }

  @Test func intValueIsExactOnly() {
    #expect(JSONNumber(42).intValue == 42)
    #expect(JSONNumber("1.0")?.intValue == 1)
    #expect(JSONNumber("1e3")?.intValue == 1000)
    #expect(JSONNumber("1.5")?.intValue == nil)
    #expect(JSONNumber("9223372036854775808")?.intValue == nil)
    #expect(JSONNumber("-9223372036854775808")?.intValue == Int.min)
  }

  @Test func decimalValueIsExactOnly() {
    #expect(
      JSONNumber("12345678901234567.89")?.decimalValue == Decimal(string: "12345678901234567.89"))
    #expect(JSONNumber("123456789012345678901234567890123456789012")?.decimalValue == nil)
  }

  @Test func doubleValueIsTheNearestDouble() {
    #expect(JSONNumber(3).doubleValue == 3)
    #expect(JSONNumber("12345678901234567.89")?.doubleValue == 12345678901234567.89)
  }

  @Test func doubleInitRejectsNonFiniteValues() {
    #expect(JSONNumber(Double.nan) == nil)
    #expect(JSONNumber(Double.infinity) == nil)
    let values: [Double] = [0.1, 1e-300, -2.5]
    #expect(values.map { JSONNumber($0)?.description } == ["0.1", "1e-300", "-2.5"])
  }

  @Test func decimalInitKeepsTheDigits() {
    #expect(JSONNumber(Decimal.nan) == nil)
    #expect(
      JSONNumber(Decimal(string: "12345678901234567.89")!)?.description == "12345678901234567.89")
  }

  @Test func integerInitAcceptsEveryWidth() {
    #expect(JSONNumber(UInt64.max).description == "18446744073709551615")
    #expect(JSONNumber(Int8.min).description == "-128")
  }

  @Test func encodingANumberNoSwiftTypeHoldsThrows() {
    let value = JSONValue.number(JSONNumber("123456789012345678901234567890123456789012.5")!)
    #expect(throws: EncodingError.self) {
      try JSONEncoder().encode(value)
    }
  }

  @Test func jsonValueAccessors() {
    let value: JSONValue = 2
    #expect(value.numberValue == 2)
    #expect(value.intValue == 2)
    #expect(value.doubleValue == 2.0)
    #expect(value.decimalValue == 2)
    #expect((value.value as? Int) == 2)
    #expect((JSONValue(floatLiteral: 2.5).value as? Double) == 2.5)
    let big = JSONValue.number(JSONNumber("12345678901234567.89")!)
    #expect((big.value as? Decimal) == Decimal(string: "12345678901234567.89"))
    #expect(JSONValue.string("1").numberValue == nil)
  }
}
