public import Foundation

/// A JSON number that keeps its exact digits.
///
/// `JSONNumber` stores a number as decimal digits and an exponent, so values that neither `Int`
/// nor `Double` holds exactly, such as `18446744073709551615` or `12345678901234567.89`, keep
/// every digit. Two numbers with the same value are equal, whatever their spelling: `1`, `1.0`,
/// and `1e0` are the same number.
///
/// ```swift
/// let price = JSONNumber("12345678901234567.89")!
/// price.description   // "12345678901234567.89"
/// price.decimalValue  // 12345678901234567.89
/// price.intValue      // nil, because the value has a fraction
/// ```
///
/// - Important: `JSONDecoder` gives a decoded number to `JSONNumber` as a `Decimal`, which holds
///   at most 38 significant digits. A number in a JSON document with more digits than that loses
///   the extra digits when it is decoded, and a number outside the range of `Decimal` keeps the
///   17 significant digits of a `Double`. Before iOS 17 and macOS 14, `JSONDecoder` reads every
///   number as a `Double` first, so a decoded number keeps only the digits of a `Double`. A number
///   created from text keeps any number of digits.
public struct JSONNumber: Sendable, Hashable {
  /// The significant digits, without leading or trailing zeros. `"0"` for zero.
  private let significand: String
  /// The power of ten that `significand` is multiplied by.
  private let exponent: Int
  private let isNegative: Bool

  /// Creates a number from the text of a JSON number, such as `"-12.5e3"`.
  ///
  /// Returns `nil` when `description` does not follow the JSON number grammar (RFC 8259), or
  /// when its power of ten is larger than `Int32.max` in magnitude. The text keeps every digit,
  /// with no limit on precision.
  public init?(_ description: String) {
    guard let parsed = Self.parse(description) else { return nil }
    self = parsed
  }

  /// Creates a number with the exact value of `value`.
  public init(_ value: some BinaryInteger) {
    self.init(String(value))!
  }

  /// Creates a number with the exact value of `value`.
  ///
  /// Returns `nil` when `value` is NaN or infinite, because JSON has no such numbers.
  public init?(_ value: Double) {
    guard value.isFinite else { return nil }
    self.init(value.description)
  }

  /// Creates a number with the exact value of `value`.
  ///
  /// Returns `nil` when `value` is NaN.
  public init?(_ value: Decimal) {
    guard !value.isNaN else { return nil }
    self.init(value.description)
  }

  /// The value as an `Int`, or `nil` when the value has a fraction or does not fit in `Int`.
  public var intValue: Int? {
    integerText.flatMap { Int($0) }
  }

  /// The `Double` nearest to the value. Some digits can be lost.
  public var doubleValue: Double {
    Double(description)!
  }

  /// The value as a `Decimal`, or `nil` when `Decimal` cannot hold it exactly.
  public var decimalValue: Decimal? {
    guard
      let decimal = Decimal(string: description, locale: Self.posixLocale),
      JSONNumber(decimal) == self
    else { return nil }
    return decimal
  }

  /// The value as a `Double`, or `nil` when `Double` cannot hold it exactly.
  var exactDoubleValue: Double? {
    let double = doubleValue
    return JSONNumber(double) == self ? double : nil
  }

  /// The value as integer text with no exponent, or `nil` when the value has a fraction or more
  /// than 20 digits, so no 64-bit integer holds it.
  private var integerText: String? {
    guard exponent >= 0, significand.count + exponent <= 20 else { return nil }
    return description
  }
}

extension JSONNumber: LosslessStringConvertible {
  /// The canonical text of the number, a valid JSON number.
  ///
  /// The text has no leading zeros and no trailing zeros after the decimal point. It uses an
  /// exponent only when plain notation would need more than 20 zeros: `100`, `0.01`, `1e40`,
  /// `1.5e-30`.
  public var description: String {
    let sign = isNegative ? "-" : ""
    if exponent >= 0, exponent <= 20 {
      return sign + significand + String(repeating: "0", count: exponent)
    }

    let digits = Array(significand)
    let integerDigitCount = digits.count + exponent
    if exponent < 0, integerDigitCount > 0 {
      return sign + String(digits[..<integerDigitCount]) + "."
        + String(digits[integerDigitCount...])
    }
    if exponent < 0, -integerDigitCount <= 20 {
      return sign + "0." + String(repeating: "0", count: -integerDigitCount) + significand
    }

    let fraction = digits.count > 1 ? "." + String(digits[1...]) : ""
    return sign + String(digits[0]) + fraction + "e" + String(integerDigitCount - 1)
  }
}

extension JSONNumber: CustomReflectable {
  public var customMirror: Mirror {
    Mirror(self, unlabeledChildren: [description], displayStyle: .struct)
  }
}

extension JSONNumber: ExpressibleByIntegerLiteral {
  public init(integerLiteral value: Int) {
    self.init(value)
  }
}

extension JSONNumber: ExpressibleByFloatLiteral {
  public init(floatLiteral value: Double) {
    guard let number = JSONNumber(value) else {
      preconditionFailure("A JSON number cannot be \(value).")
    }
    self = number
  }
}

extension JSONNumber: Codable {
  /// Decodes a number as a `Decimal`, which keeps up to 38 significant digits. A number outside
  /// the range of `Decimal` is decoded as a `Double`.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    let decimal = try? container.decode(Decimal.self)
    let double = try? container.decode(Double.self)
    var decimalIsBuiltFromDouble = true
    if #available(macOS 14, iOS 17, macCatalyst 17, tvOS 17, watchOS 10, *) {
      decimalIsBuiltFromDouble = false
    }
    if let number = Self.decoded(
      decimal: decimal, double: double, decimalIsBuiltFromDouble: decimalIsBuiltFromDouble)
    {
      self = number
    } else {
      throw DecodingError.typeMismatch(
        JSONNumber.self,
        .init(codingPath: decoder.codingPath, debugDescription: "Expected a JSON number.")
      )
    }
  }

  /// The number that `JSONDecoder` read as `decimal` and as `double`.
  ///
  /// Before iOS 17 and macOS 14, `JSONDecoder` builds a `Decimal` from the parsed `Double`, so
  /// `3.133` decodes as `3.132999999999999488`. The shortest text of the `Double` is closer to the
  /// document then.
  static func decoded(
    decimal: Decimal?, double: Double?, decimalIsBuiltFromDouble: Bool
  ) -> JSONNumber? {
    if decimalIsBuiltFromDouble, let double, let number = JSONNumber(double) {
      return number
    }
    return decimal.flatMap(JSONNumber.init) ?? double.flatMap(JSONNumber.init)
  }

  /// Encodes the number as the first Swift type that holds it exactly: `Int64`, `UInt64`,
  /// `Double`, then `Decimal`.
  ///
  /// - Throws: `EncodingError.invalidValue` when none of these types holds the value exactly.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    let integerText = integerText
    if let integer = integerText.flatMap({ Int64($0) }) {
      try container.encode(integer)
    } else if let integer = integerText.flatMap({ UInt64($0) }) {
      try container.encode(integer)
    } else if let double = exactDoubleValue {
      try container.encode(double)
    } else if let decimal = decimalValue {
      try container.encode(decimal)
    } else {
      throw EncodingError.invalidValue(
        self,
        .init(
          codingPath: encoder.codingPath,
          debugDescription: "No Swift number type holds \(description) exactly."
        )
      )
    }
  }
}

extension JSONNumber {
  /// The largest exponent magnitude a number can have, so that arithmetic on the exponent and the
  /// digit count cannot overflow.
  private static let maximumExponent = Int(Int32.max)

  private static let posixLocale = Locale(identifier: "en_US_POSIX")

  /// Parses `-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?` into its canonical form.
  private static func parse(_ text: String) -> JSONNumber? {
    var bytes = Substring(text).utf8[...]
    let isDigit = { (byte: UInt8) in byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9") }

    let isNegative = bytes.first == UInt8(ascii: "-")
    if isNegative { bytes = bytes.dropFirst() }

    let integerDigits = bytes.prefix(while: isDigit)
    guard !integerDigits.isEmpty else { return nil }
    if integerDigits.count > 1, integerDigits.first == UInt8(ascii: "0") { return nil }
    bytes = bytes.dropFirst(integerDigits.count)

    var fractionDigits = bytes.prefix(0)
    if bytes.first == UInt8(ascii: ".") {
      bytes = bytes.dropFirst()
      fractionDigits = bytes.prefix(while: isDigit)
      guard !fractionDigits.isEmpty else { return nil }
      bytes = bytes.dropFirst(fractionDigits.count)
    }

    var exponent = 0
    if bytes.first == UInt8(ascii: "e") || bytes.first == UInt8(ascii: "E") {
      bytes = bytes.dropFirst()
      var exponentIsNegative = false
      if bytes.first == UInt8(ascii: "+") || bytes.first == UInt8(ascii: "-") {
        exponentIsNegative = bytes.first == UInt8(ascii: "-")
        bytes = bytes.dropFirst()
      }
      let exponentDigits = bytes.prefix(while: isDigit)
      guard !exponentDigits.isEmpty, let magnitude = Int(String(exponentDigits)!) else {
        return nil
      }
      exponent = exponentIsNegative ? -magnitude : magnitude
      bytes = bytes.dropFirst(exponentDigits.count)
    }
    guard bytes.isEmpty else { return nil }

    var digits = Substring(String(integerDigits)! + String(fractionDigits)!)
    let (shifted, overflow) = exponent.subtractingReportingOverflow(fractionDigits.count)
    guard !overflow else { return nil }
    exponent = shifted

    digits = digits.drop { $0 == "0" }
    guard !digits.isEmpty else {
      return JSONNumber(significand: "0", exponent: 0, isNegative: false)
    }
    let trailingZeros = digits.reversed().prefix { $0 == "0" }.count
    digits = digits.dropLast(trailingZeros)
    let (adjusted, adjustOverflow) = exponent.addingReportingOverflow(trailingZeros)
    guard !adjustOverflow, abs(adjusted) <= maximumExponent else { return nil }

    return JSONNumber(significand: String(digits), exponent: adjusted, isNegative: isNegative)
  }

  private init(significand: String, exponent: Int, isNegative: Bool) {
    self.significand = significand
    self.exponent = exponent
    self.isNegative = isNegative
  }
}
