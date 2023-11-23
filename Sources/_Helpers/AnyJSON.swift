import Foundation

/// An enumeration that represents JSON-compatible values of various types.
public enum AnyJSON: Sendable, Codable, Hashable {
  /// Represents a `null` JSON value.
  case null
  /// Represents a JSON boolean value.
  case bool(Bool)
  /// Represents a JSON number (floating-point) value.
  case number(Double)
  /// Represents a JSON string value.
  case string(String)
  /// Represents a JSON object (dictionary) value.
  case object([String: AnyJSON])
  /// Represents a JSON array (list) value.
  case array([AnyJSON])

  /// Returns the underlying Swift value corresponding to the `AnyJSON` instance.
  ///
  /// - Note: For `.object` and `.array` cases, the returned value contains recursively transformed
  /// `AnyJSON` instances.
  public var value: Any? {
    switch self {
    case .null: return nil
    case let .string(string): return string
    case let .number(double): return double
    case let .object(dictionary): return dictionary.mapValues(\.value)
    case let .array(array): return array.map(\.value)
    case let .bool(bool): return bool
    }
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let object = try? container.decode([String: AnyJSON].self) {
      self = .object(object)
    } else if let array = try? container.decode([AnyJSON].self) {
      self = .array(array)
    } else if let string = try? container.decode(String.self) {
      self = .string(string)
    } else if let bool = try? container.decode(Bool.self) {
      self = .bool(bool)
    } else if let number = try? container.decode(Double.self) {
      self = .number(number)
    } else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: "Invalid JSON value.")
      )
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .null: try container.encodeNil()
    case let .array(array): try container.encode(array)
    case let .object(object): try container.encode(object)
    case let .string(string): try container.encode(string)
    case let .number(number): try container.encode(number)
    case let .bool(bool): try container.encode(bool)
    }
  }
}

extension AnyJSON {
  public var objectValue: [String: AnyJSON]? {
    if case let .object(object) = self {
      return object
    }
    return nil
  }

  public var arrayValue: [AnyJSON]? {
    if case let .array(array) = self {
      return array
    }
    return nil
  }

  public var stringValue: String? {
    if case let .string(string) = self {
      return string
    }
    return nil
  }

  public var numberValue: Double? {
    if case let .number(number) = self {
      return number
    }
    return nil
  }

  public var boolValue: Bool? {
    if case let .bool(bool) = self {
      return bool
    }
    return nil
  }
}

extension AnyJSON: ExpressibleByNilLiteral {
  public init(nilLiteral _: ()) {
    self = .null
  }
}

extension AnyJSON: ExpressibleByStringLiteral {
  public init(stringLiteral value: String) {
    self = .string(value)
  }
}

extension AnyJSON: ExpressibleByArrayLiteral {
  public init(arrayLiteral elements: AnyJSON...) {
    self = .array(elements)
  }
}

extension AnyJSON: ExpressibleByIntegerLiteral {
  public init(integerLiteral value: Int) {
    self = .number(Double(value))
  }
}

extension AnyJSON: ExpressibleByFloatLiteral {
  public init(floatLiteral value: Double) {
    self = .number(value)
  }
}

extension AnyJSON: ExpressibleByBooleanLiteral {
  public init(booleanLiteral value: Bool) {
    self = .bool(value)
  }
}

extension AnyJSON: ExpressibleByDictionaryLiteral {
  public init(dictionaryLiteral elements: (String, AnyJSON)...) {
    self = .object(Dictionary(uniqueKeysWithValues: elements))
  }
}
