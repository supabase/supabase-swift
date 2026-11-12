public import Foundation

/// A JSON object: a dictionary of ``JSONValue`` values by key.
public typealias JSONObject = [String: JSONValue]
/// A JSON array: a list of ``JSONValue`` values.
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

  /// `true` when the value is `null`.
  public var isNil: Bool {
    if case .null = self {
      return true
    }

    return false
  }

  /// The boolean, or `nil` when the value is not a boolean.
  public var boolValue: Bool? {
    if case .bool(let val) = self {
      return val
    }
    return nil
  }

  /// The object, or `nil` when the value is not an object.
  public var objectValue: JSONObject? {
    if case .object(let dictionary) = self {
      return dictionary
    }
    return nil
  }

  /// The array, or `nil` when the value is not an array.
  public var arrayValue: JSONArray? {
    if case .array(let array) = self {
      return array
    }
    return nil
  }

  /// The string, or `nil` when the value is not a string.
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

  /// Decodes a JSON value of any type.
  ///
  /// - Parameter decoder: The decoder to read from.
  /// - Throws: `DecodingError.dataCorrupted` when the data holds no JSON value.
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

  /// Encodes the value as the JSON type of its case.
  ///
  /// - Parameter encoder: The encoder to write to.
  /// - Throws: The error of the encoder. A ``number(_:)`` also throws
  ///   `EncodingError.invalidValue` when no Swift number type holds it exactly.
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
  /// Creates a ``null`` value from a `nil` literal.
  public init(nilLiteral _: ()) {
    self = .null
  }
}

extension JSONValue: ExpressibleByStringLiteral {
  /// Creates a ``string(_:)`` value from a string literal.
  public init(stringLiteral value: String) {
    self = .string(value)
  }
}

extension JSONValue: ExpressibleByArrayLiteral {
  /// Creates an ``array(_:)`` value from an array literal.
  public init(arrayLiteral elements: JSONValue...) {
    self = .array(elements)
  }
}

extension JSONValue: ExpressibleByIntegerLiteral {
  /// Creates a ``number(_:)`` value from an integer literal.
  public init(integerLiteral value: Int) {
    self = .number(JSONNumber(integerLiteral: value))
  }
}

extension JSONValue: ExpressibleByFloatLiteral {
  /// Creates a ``number(_:)`` value from a floating-point literal.
  public init(floatLiteral value: Double) {
    self = .number(JSONNumber(floatLiteral: value))
  }
}

extension JSONValue: ExpressibleByBooleanLiteral {
  /// Creates a ``bool(_:)`` value from a boolean literal.
  public init(booleanLiteral value: Bool) {
    self = .bool(value)
  }
}

extension JSONValue: ExpressibleByDictionaryLiteral {
  /// Creates an ``object(_:)`` value from a dictionary literal. The keys must be unique.
  public init(dictionaryLiteral elements: (String, JSONValue)...) {
    self = .object(Dictionary(uniqueKeysWithValues: elements))
  }
}

extension JSONValue: CustomStringConvertible {
  /// The description of ``value``, the underlying Swift value.
  public var description: String {
    String(describing: value)
  }
}
