import Foundation

public typealias JSONObject = [String: AnyJSON]
public typealias JSONArray = [AnyJSON]

/// An enumeration that represents JSON-compatible values of various types.
public enum AnyJSON: Sendable, Codable, Hashable {
  /// Represents a `null` JSON value.
  case null
  /// Represents a JSON boolean value.
  case bool(Bool)
  /// Represents a JSON number (integer) value.
  case integer(Int)
  /// Represents a JSON number (floating-point) value.
  case double(Double)
  /// Represents a JSON string value.
  case string(String)
  /// Represents a JSON object (dictionary) value.
  case object(JSONObject)
  /// Represents a JSON array (list) value.
  case array(JSONArray)

  /// Returns the underlying Swift value corresponding to the `AnyJSON` instance.
  ///
  /// - Note: For `.object` and `.array` cases, the returned value contains recursively transformed `AnyJSON` instances.
  public var value: Any {
    switch self {
    case .null: NSNull()
    case .string(let string): string
    case .integer(let val): val
    case .double(let val): val
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

  public var intValue: Int? {
    if case .integer(let val) = self {
      return val
    }
    return nil
  }

  public var doubleValue: Double? {
    if case .double(let val) = self {
      return val
    }
    return nil
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()

    if container.decodeNil() {
      self = .null
    } else if let val = try? container.decode(Int.self) {
      self = .integer(val)
    } else if let val = try? container.decode(Double.self) {
      self = .double(val)
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
    case .integer(let val): try container.encode(val)
    case .double(let val): try container.encode(val)
    case .bool(let val): try container.encode(val)
    }
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
    self = .integer(value)
  }
}

extension AnyJSON: ExpressibleByFloatLiteral {
  public init(floatLiteral value: Double) {
    self = .double(value)
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

extension AnyJSON: CustomStringConvertible {
  public var description: String {
    String(describing: value)
  }
}
