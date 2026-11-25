//
//  IcebergSchema.swift
//  StorageIceberg
//
//  Created by Guilherme Souza on 25/11/26.
//

public import Helpers

/// The schema of an Iceberg table: its top-level fields.
///
/// - Warning: Experimental. See ``IcebergCatalog``.
@_spi(Experimental)
public struct IcebergSchema: Codable, Hashable, Sendable {
  /// The schema ID. The catalog assigns it when you leave it `nil`.
  public var schemaID: Int?

  /// The top-level fields.
  public var fields: [IcebergField]

  /// The IDs of the fields that identify a row, if any.
  public var identifierFieldIDs: [Int]?

  /// Creates an ``IcebergSchema``.
  public init(schemaID: Int? = nil, fields: [IcebergField], identifierFieldIDs: [Int]? = nil) {
    self.schemaID = schemaID
    self.fields = fields
    self.identifierFieldIDs = identifierFieldIDs
  }

  private enum CodingKeys: String, CodingKey {
    case type
    case schemaID = "schema-id"
    case fields
    case identifierFieldIDs = "identifier-field-ids"
  }

  /// Decodes a schema. The `type` key, always `struct`, is ignored.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    schemaID = try container.decodeIfPresent(Int.self, forKey: .schemaID)
    fields = try container.decode([IcebergField].self, forKey: .fields)
    identifierFieldIDs = try container.decodeIfPresent([Int].self, forKey: .identifierFieldIDs)
  }

  /// Encodes the schema with `type` set to `struct`.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode("struct", forKey: .type)
    try container.encodeIfPresent(schemaID, forKey: .schemaID)
    try container.encode(fields, forKey: .fields)
    try container.encodeIfPresent(identifierFieldIDs, forKey: .identifierFieldIDs)
  }
}

/// A field of an Iceberg schema or of a nested struct.
///
/// - Warning: Experimental. See ``IcebergCatalog``.
@_spi(Experimental)
public struct IcebergField: Codable, Hashable, Sendable {
  /// The field ID, unique in the table.
  public var id: Int

  /// The field name.
  public var name: String

  /// The field type.
  public var type: IcebergType

  /// Whether every row must have a value for the field.
  public var isRequired: Bool

  /// The field documentation, if any.
  public var doc: String?

  /// Creates an ``IcebergField``.
  public init(id: Int, name: String, type: IcebergType, isRequired: Bool, doc: String? = nil) {
    self.id = id
    self.name = name
    self.type = type
    self.isRequired = isRequired
    self.doc = doc
  }

  private enum CodingKeys: String, CodingKey {
    case id, name, type
    case isRequired = "required"
    case doc
  }
}

/// The type of an Iceberg field.
///
/// A primitive type is a string on the wire, such as `long` or `decimal(10, 2)`. A nested type is
/// an object whose `type` is `struct`, `list`, or `map`. Any other value decodes to ``unknown(_:)``
/// and encodes back unchanged.
///
/// New cases arrive only in a major release.
///
/// - Warning: Experimental. See ``IcebergCatalog``.
@_spi(Experimental)
public indirect enum IcebergType: Codable, Hashable, Sendable {
  /// A primitive type.
  case primitive(IcebergPrimitiveType)

  /// A struct of nested fields.
  case `struct`([IcebergField])

  /// A list of elements.
  case list(IcebergListType)

  /// A map from keys to values.
  case map(IcebergMapType)

  /// A type this SDK does not know, as the catalog sent it.
  case unknown(JSONValue)

  /// The `boolean` type.
  public static let boolean = IcebergType.primitive(.boolean)
  /// The `int` type: a 32-bit signed integer.
  public static let int = IcebergType.primitive(.int)
  /// The `long` type: a 64-bit signed integer.
  public static let long = IcebergType.primitive(.long)
  /// The `float` type: a 32-bit floating-point number.
  public static let float = IcebergType.primitive(.float)
  /// The `double` type: a 64-bit floating-point number.
  public static let double = IcebergType.primitive(.double)
  /// The `date` type: a calendar date without a time.
  public static let date = IcebergType.primitive(.date)
  /// The `time` type: a time of day in microseconds, without a date or time zone.
  public static let time = IcebergType.primitive(.time)
  /// The `timestamp` type: a date and time in microseconds, without a time zone.
  public static let timestamp = IcebergType.primitive(.timestamp)
  /// The `timestamptz` type: a date and time in microseconds, stored as UTC.
  public static let timestamptz = IcebergType.primitive(.timestamptz)
  /// The `string` type: UTF-8 text.
  public static let string = IcebergType.primitive(.string)
  /// The `uuid` type.
  public static let uuid = IcebergType.primitive(.uuid)
  /// The `binary` type: bytes of any length.
  public static let binary = IcebergType.primitive(.binary)

  /// The `decimal(P, S)` type.
  ///
  /// - Parameters:
  ///   - precision: The number of digits.
  ///   - scale: The number of digits after the decimal point.
  public static func decimal(precision: Int, scale: Int) -> IcebergType {
    .primitive(.decimal(precision: precision, scale: scale))
  }

  /// The `fixed[L]` type: bytes of a fixed length.
  ///
  /// - Parameter length: The number of bytes.
  public static func fixed(length: Int) -> IcebergType {
    .primitive(.fixed(length: length))
  }

  private enum StructCodingKeys: String, CodingKey {
    case type, fields
  }

  /// Decodes a type from a string or from a nested type object.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let name = try? container.decode(String.self) {
      self = .primitive(IcebergPrimitiveType(rawValue: name))
      return
    }

    if let keyed = try? decoder.container(keyedBy: StructCodingKeys.self),
      let type = try? keyed.decode(String.self, forKey: .type)
    {
      switch type {
      case "struct":
        self = .struct(try keyed.decode([IcebergField].self, forKey: .fields))
        return
      case "list":
        self = .list(try IcebergListType(from: decoder))
        return
      case "map":
        self = .map(try IcebergMapType(from: decoder))
        return
      default:
        break
      }
    }
    self = .unknown(try container.decode(JSONValue.self))
  }

  /// Encodes the type in the form ``init(from:)`` reads.
  public func encode(to encoder: any Encoder) throws {
    switch self {
    case .primitive(let primitive):
      var container = encoder.singleValueContainer()
      try container.encode(primitive.rawValue)
    case .struct(let fields):
      var container = encoder.container(keyedBy: StructCodingKeys.self)
      try container.encode("struct", forKey: .type)
      try container.encode(fields, forKey: .fields)
    case .list(let list):
      try list.encode(to: encoder)
    case .map(let map):
      try map.encode(to: encoder)
    case .unknown(let value):
      var container = encoder.singleValueContainer()
      try container.encode(value)
    }
  }
}

/// The name of a primitive Iceberg type, such as `long` or `decimal(10, 2)`.
///
/// - Warning: Experimental. See ``IcebergCatalog``.
@_spi(Experimental)
public struct IcebergPrimitiveType: RawRepresentable, Codable, Hashable, Sendable,
  ExpressibleByStringLiteral
{
  /// The type name as the catalog spells it.
  public let rawValue: String

  /// Creates an ``IcebergPrimitiveType`` from its name.
  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// Creates an ``IcebergPrimitiveType`` from its name.
  public init(stringLiteral value: String) {
    self.init(rawValue: value)
  }

  /// `boolean`.
  public static let boolean: IcebergPrimitiveType = "boolean"
  /// `int`: a 32-bit signed integer.
  public static let int: IcebergPrimitiveType = "int"
  /// `long`: a 64-bit signed integer.
  public static let long: IcebergPrimitiveType = "long"
  /// `float`: a 32-bit floating-point number.
  public static let float: IcebergPrimitiveType = "float"
  /// `double`: a 64-bit floating-point number.
  public static let double: IcebergPrimitiveType = "double"
  /// `date`: a calendar date without a time.
  public static let date: IcebergPrimitiveType = "date"
  /// `time`: a time of day in microseconds, without a date or time zone.
  public static let time: IcebergPrimitiveType = "time"
  /// `timestamp`: a date and time in microseconds, without a time zone.
  public static let timestamp: IcebergPrimitiveType = "timestamp"
  /// `timestamptz`: a date and time in microseconds, stored as UTC.
  public static let timestamptz: IcebergPrimitiveType = "timestamptz"
  /// `timestamp_ns`: a date and time in nanoseconds, without a time zone.
  public static let timestampNs: IcebergPrimitiveType = "timestamp_ns"
  /// `timestamptz_ns`: a date and time in nanoseconds, stored as UTC.
  public static let timestamptzNs: IcebergPrimitiveType = "timestamptz_ns"
  /// `string`: UTF-8 text.
  public static let string: IcebergPrimitiveType = "string"
  /// `uuid`.
  public static let uuid: IcebergPrimitiveType = "uuid"
  /// `binary`: bytes of any length.
  public static let binary: IcebergPrimitiveType = "binary"

  /// `decimal(P, S)`.
  ///
  /// - Parameters:
  ///   - precision: The number of digits.
  ///   - scale: The number of digits after the decimal point.
  public static func decimal(precision: Int, scale: Int) -> IcebergPrimitiveType {
    IcebergPrimitiveType(rawValue: "decimal(\(precision), \(scale))")
  }

  /// `fixed[L]`: bytes of a fixed length.
  ///
  /// - Parameter length: The number of bytes.
  public static func fixed(length: Int) -> IcebergPrimitiveType {
    IcebergPrimitiveType(rawValue: "fixed[\(length)]")
  }
}

/// An Iceberg list type: elements of one type.
///
/// - Warning: Experimental. See ``IcebergCatalog``.
@_spi(Experimental)
public struct IcebergListType: Codable, Hashable, Sendable {
  /// The field ID of the element.
  public var elementID: Int

  /// The element type.
  public var element: IcebergType

  /// Whether every element must have a value.
  public var isElementRequired: Bool

  /// Creates an ``IcebergListType``.
  public init(elementID: Int, element: IcebergType, isElementRequired: Bool) {
    self.elementID = elementID
    self.element = element
    self.isElementRequired = isElementRequired
  }

  private enum CodingKeys: String, CodingKey {
    case type
    case elementID = "element-id"
    case element
    case isElementRequired = "element-required"
  }

  /// Decodes a list type. The `type` key, always `list`, is ignored.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    elementID = try container.decode(Int.self, forKey: .elementID)
    element = try container.decode(IcebergType.self, forKey: .element)
    isElementRequired = try container.decode(Bool.self, forKey: .isElementRequired)
  }

  /// Encodes the list type with `type` set to `list`.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode("list", forKey: .type)
    try container.encode(elementID, forKey: .elementID)
    try container.encode(element, forKey: .element)
    try container.encode(isElementRequired, forKey: .isElementRequired)
  }
}

/// An Iceberg map type: keys of one type mapped to values of another.
///
/// - Warning: Experimental. See ``IcebergCatalog``.
@_spi(Experimental)
public struct IcebergMapType: Codable, Hashable, Sendable {
  /// The field ID of the key.
  public var keyID: Int

  /// The key type.
  public var key: IcebergType

  /// The field ID of the value.
  public var valueID: Int

  /// The value type.
  public var value: IcebergType

  /// Whether every value must be present.
  public var isValueRequired: Bool

  /// Creates an ``IcebergMapType``.
  public init(
    keyID: Int, key: IcebergType, valueID: Int, value: IcebergType, isValueRequired: Bool
  ) {
    self.keyID = keyID
    self.key = key
    self.valueID = valueID
    self.value = value
    self.isValueRequired = isValueRequired
  }

  private enum CodingKeys: String, CodingKey {
    case type
    case keyID = "key-id"
    case key
    case valueID = "value-id"
    case value
    case isValueRequired = "value-required"
  }

  /// Decodes a map type. The `type` key, always `map`, is ignored.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    keyID = try container.decode(Int.self, forKey: .keyID)
    key = try container.decode(IcebergType.self, forKey: .key)
    valueID = try container.decode(Int.self, forKey: .valueID)
    value = try container.decode(IcebergType.self, forKey: .value)
    isValueRequired = try container.decode(Bool.self, forKey: .isValueRequired)
  }

  /// Encodes the map type with `type` set to `map`.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode("map", forKey: .type)
    try container.encode(keyID, forKey: .keyID)
    try container.encode(key, forKey: .key)
    try container.encode(valueID, forKey: .valueID)
    try container.encode(value, forKey: .value)
    try container.encode(isValueRequired, forKey: .isValueRequired)
  }
}
