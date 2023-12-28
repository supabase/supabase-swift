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
  /// - Note: For `.object` and `.array` cases, the returned value contains recursively transformed
  /// `AnyJSON` instances.
  public var value: Any {
    switch self {
    case .null: return NSNull()
    case let .string(string): return string
    case let .integer(val): return val
    case let .double(val): return val
    case let .object(dictionary): return dictionary.mapValues(\.value)
    case let .array(array): return array.map(\.value)
    case let .bool(bool): return bool
    }
  }

  public var isNil: Bool {
    if case .null = self {
      return true
    }

    return false
  }

  public var boolValue: Bool? {
    if case let .bool(val) = self {
      return val
    }
    return nil
  }

  public var objectValue: JSONObject? {
    if case let .object(dictionary) = self {
      return dictionary
    }
    return nil
  }

  public var arrayValue: JSONArray? {
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
    if case let .integer(val) = self {
      return val
    }
    return nil
  }

  public var doubleValue: Double? {
    if case let .double(val) = self {
      return val
    }
    return nil
  }

  public init(from decoder: Decoder) throws {
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

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .null: try container.encodeNil()
    case let .array(val): try container.encode(val)
    case let .object(val): try container.encode(val)
    case let .string(val): try container.encode(val)
    case let .integer(val): try container.encode(val)
    case let .double(val): try container.encode(val)
    case let .bool(val): try container.encode(val)
    }
  }

  public func decode<T: Decodable>(_: T.Type) throws -> T {
    let data = try AnyJSON.encoder.encode(self)
    return try AnyJSON.decoder.decode(T.self, from: data)
  }
}

extension JSONObject {
  public func decode<T: Decodable>(_: T.Type) throws -> T {
    let data = try AnyJSON.encoder.encode(self)
    return try AnyJSON.decoder.decode(T.self, from: data)
  }
}

extension JSONArray {
  public func decode<T: Decodable>(_: T.Type) throws -> [T] {
    let data = try AnyJSON.encoder.encode(self)
    return try AnyJSON.decoder.decode([T].self, from: data)
  }
}

extension AnyJSON {
  /// The decoder instance used for transforming AnyJSON to some Codable type.
  public static let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dataDecodingStrategy = .base64
    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      let dateString = try container.decode(String.self)

      let date = DateFormatter.iso8601.date(from: dateString) ?? DateFormatter
        .iso8601_noMilliseconds.date(from: dateString)

      guard let decodedDate = date else {
        throw DecodingError.typeMismatch(
          Date.self,
          DecodingError.Context(
            codingPath: container.codingPath,
            debugDescription: "String is not a valid Date"
          )
        )
      }

      return decodedDate
    }
    return decoder
  }()

  /// The encoder instance used for transforming AnyJSON to some Codable type.
  public static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.dataEncodingStrategy = .base64
    encoder.dateEncodingStrategy = .formatted(DateFormatter.iso8601)
    return encoder
  }()
}

extension AnyJSON {
  public init(_ value: some Codable) throws {
    if let value = value as? AnyJSON {
      self = value
    } else {
      let data = try AnyJSON.encoder.encode(value)
      self = try AnyJSON.decoder.decode(AnyJSON.self, from: data)
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
