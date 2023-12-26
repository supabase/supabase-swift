import Foundation

/// An enumeration that represents JSON-compatible values of various types.
public enum AnyJSON: Sendable, Codable, Hashable {
  /// Represents a `null` JSON value.
  case null
  /// Represents a JSON boolean value.
  case bool(Bool)
  /// Represents a JSON number (floating-point) value.
  case number(NSNumber)
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
  public var value: Any {
    switch self {
    case .null: return NSNull()
    case let .string(string): return string
    case let .number(number): return number
    case let .object(dictionary): return dictionary.mapValues(\.value)
    case let .array(array): return array.map(\.value)
    case let .bool(bool): return bool
    }
  }

  public var objectValue: [String: AnyJSON]? {
    if case let .object(dictionary) = self {
      return dictionary
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

  public var intValue: Int? {
    if case let .number(nSNumber) = self {
      return nSNumber.intValue
    }
    return nil
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()

    if container.decodeNil() {
      self = .null
    } else if let val = try? container.decode(Int.self) {
      self = .number(val as NSNumber)
    } else if let val = try? container.decode(Int8.self) {
      self = .number(val as NSNumber)
    } else if let val = try? container.decode(Int16.self) {
      self = .number(val as NSNumber)
    } else if let val = try? container.decode(Int32.self) {
      self = .number(val as NSNumber)
    } else if let val = try? container.decode(Int64.self) {
      self = .number(val as NSNumber)
    } else if let val = try? container.decode(UInt.self) {
      self = .number(val as NSNumber)
    } else if let val = try? container.decode(UInt8.self) {
      self = .number(val as NSNumber)
    } else if let val = try? container.decode(UInt16.self) {
      self = .number(val as NSNumber)
    } else if let val = try? container.decode(UInt32.self) {
      self = .number(val as NSNumber)
    } else if let val = try? container.decode(UInt64.self) {
      self = .number(val as NSNumber)
    } else if let val = try? container.decode(Double.self) {
      self = .number(val as NSNumber)
    } else if let val = try? container.decode(String.self) {
      self = .string(val)
    } else if let val = try? container.decode([AnyJSON].self) {
      self = .array(val)
    } else if let val = try? container.decode([String: AnyJSON].self) {
      self = .object(val)
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
    case let .number(number): try encodeRawNumber(number, into: &container)
    case let .bool(bool): try container.encode(bool)
    }
  }

  private func encodeRawNumber(
    _ number: NSNumber,
    into container: inout SingleValueEncodingContainer
  ) throws {
    switch number {
    case let intValue as Int:
      try container.encode(intValue)
    case let int8Value as Int8:
      try container.encode(int8Value)
    case let int32Value as Int32:
      try container.encode(int32Value)
    case let int64Value as Int64:
      try container.encode(int64Value)
    case let uintValue as UInt:
      try container.encode(uintValue)
    case let uint8Value as UInt8:
      try container.encode(uint8Value)
    case let uint16Value as UInt16:
      try container.encode(uint16Value)
    case let uint32Value as UInt32:
      try container.encode(uint32Value)
    case let uint64Value as UInt64:
      try container.encode(uint64Value)
    case let double as Double:
      try container.encode(double)
    default:
      try container.encodeNil()
    }
  }

  public func decode<T: Decodable>(_: T.Type) throws -> T {
    let data = try AnyJSON.encoder.encode(self)
    return try AnyJSON.decoder.decode(T.self, from: data)
  }
}

extension AnyJSON {
  public static var decoder: JSONDecoder = .init()
  public static var encoder: JSONEncoder = .init()
}

extension AnyJSON {
  public init(_ value: Any) {
    switch value {
    case let value as AnyJSON:
      self = value
    case let intValue as Int:
      self = .number(intValue as NSNumber)
    case let intValue as Int8:
      self = .number(intValue as NSNumber)
    case let intValue as Int16:
      self = .number(intValue as NSNumber)
    case let intValue as Int32:
      self = .number(intValue as NSNumber)
    case let intValue as Int64:
      self = .number(intValue as NSNumber)
    case let intValue as UInt:
      self = .number(intValue as NSNumber)
    case let intValue as UInt8:
      self = .number(intValue as NSNumber)
    case let intValue as UInt16:
      self = .number(intValue as NSNumber)
    case let intValue as UInt32:
      self = .number(intValue as NSNumber)
    case let intValue as UInt64:
      self = .number(intValue as NSNumber)
    case let doubleValue as Float:
      self = .number(doubleValue as NSNumber)
    case let doubleValue as Double:
      self = .number(doubleValue as NSNumber)
    case let doubleValue as Decimal:
      self = .number(doubleValue as NSNumber)
    case let numberValue as NSNumber:
      self = .number(numberValue as NSNumber)
    case let value as String:
      self = .string(value)
    case let value as Bool:
      self = .bool(value)
    case _ as NSNull:
      self = .null
    case let value as [Any]:
      self = .array(value.compactMap(AnyJSON.init))
    case let value as [String: Any]:
      self = .object(value.compactMapValues(AnyJSON.init))
    case let value as any Codable:
      let data = try! JSONEncoder().encode(value)
      let json = try! JSONSerialization.jsonObject(with: data)
      self = AnyJSON(json)
    default:
      print("Failed to create AnyJSON with: \(value)")
      self = .null
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
    self = .number(value as NSNumber)
  }
}

extension AnyJSON: ExpressibleByFloatLiteral {
  public init(floatLiteral value: Double) {
    self = .number(value as NSNumber)
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
