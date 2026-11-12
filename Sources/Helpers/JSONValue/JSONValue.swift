public import Foundation

public typealias JSONObject = [String: JSONValue]
public typealias JSONArray = [JSONValue]

/// An enumeration that represents JSON-compatible values of various types.
public enum JSONValue: Sendable, Codable, Hashable {
  /// Represents a `null` JSON value.
  case null
  /// Represents a JSON boolean value.
  case bool(Bool)
  /// Represents a JSON number value, with its exact digits.
  case number(JSONNumber)
  /// Represents a JSON string value.
  case string(String)
  /// Represents a JSON object (dictionary) value.
  case object(JSONObject)
  /// Represents a JSON array (list) value.
  case array(JSONArray)

  /// Returns the underlying Swift value corresponding to the `JSONValue` instance.
  ///
  /// A `.number` is an `Int` when it is an integer that fits in `Int`, a `Double` when a `Double`
  /// holds it exactly, a `Decimal` when a `Decimal` holds it exactly, and otherwise the nearest
  /// `Double`.
  ///
  /// - Note: For `.object` and `.array` cases, the returned value contains recursively transformed `JSONValue` instances.
  public var value: Any {
    switch self {
    case .null: NSNull()
    case .string(let string): string
    case .number(let number):
      if let int = number.intValue {
        int
      } else if let double = number.exactDoubleValue {
        double
      } else if let decimal = number.decimalValue {
        decimal
      } else {
        number.doubleValue
      }
    case .object(let dictionary): dictionary.mapValues(\.value)
    case .array(let array): array.map(\.value)
    case .bool(let bool): bool
    }
  }

  public var isNil: Bool {
    if case .null = self {
      return true
    }

    return false
  }

  public var boolValue: Bool? {
    if case .bool(let val) = self {
      return val
    }
    return nil
  }

  public var objectValue: JSONObject? {
    if case .object(let dictionary) = self {
      return dictionary
    }
    return nil
  }

  public var arrayValue: JSONArray? {
    if case .array(let array) = self {
      return array
    }
    return nil
  }

  public var stringValue: String? {
    if case .string(let string) = self {
      return string
    }
    return nil
  }

  /// The number, or `nil` when the value is not a number.
  public var numberValue: JSONNumber? {
    if case .number(let number) = self {
      return number
    }
    return nil
  }

  /// The number as an `Int`, or `nil` when the value is not a number, has a fraction, or does
  /// not fit in `Int`.
  public var intValue: Int? {
    numberValue?.intValue
  }

  /// The `Double` nearest to the number, or `nil` when the value is not a number.
  public var doubleValue: Double? {
    numberValue?.doubleValue
  }

  /// The number as a `Decimal`, or `nil` when the value is not a number or `Decimal` cannot hold
  /// it exactly.
  public var decimalValue: Decimal? {
    numberValue?.decimalValue
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()

    if container.decodeNil() {
      self = .null
    } else if let val = try? container.decode(JSONNumber.self) {
      self = .number(val)
    } else if let val = try? container.decode(String.self) {
      self = .string(val)
    } else if let val = try? container.decode(Bool.self) {
      self = .bool(val)
    } else if let val = try? container.decode(JSONArray.self) {
      self = .array(val)
    } else if let val = try? container.decode(JSONObject.self) {
      self = .object(val)
    } else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: "Invalid JSON value.")
      )
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .null: try container.encodeNil()
    case .array(let val): try container.encode(val)
    case .object(let val): try container.encode(val)
    case .string(let val): try container.encode(val)
    case .number(let val): try container.encode(val)
    case .bool(let val): try container.encode(val)
    }
  }
}

extension JSONValue: ExpressibleByNilLiteral {
  public init(nilLiteral _: ()) {
    self = .null
  }
}

extension JSONValue: ExpressibleByStringLiteral {
  public init(stringLiteral value: String) {
    self = .string(value)
  }
}

extension JSONValue: ExpressibleByArrayLiteral {
  public init(arrayLiteral elements: JSONValue...) {
    self = .array(elements)
  }
}

extension JSONValue: ExpressibleByIntegerLiteral {
  public init(integerLiteral value: Int) {
    self = .number(JSONNumber(integerLiteral: value))
  }
}

extension JSONValue: ExpressibleByFloatLiteral {
  public init(floatLiteral value: Double) {
    self = .number(JSONNumber(floatLiteral: value))
  }
}

extension JSONValue: ExpressibleByBooleanLiteral {
  public init(booleanLiteral value: Bool) {
    self = .bool(value)
  }
}

extension JSONValue: ExpressibleByDictionaryLiteral {
  public init(dictionaryLiteral elements: (String, JSONValue)...) {
    self = .object(Dictionary(uniqueKeysWithValues: elements))
  }
}

extension JSONValue: CustomStringConvertible {
  public var description: String {
    String(describing: value)
  }
}
