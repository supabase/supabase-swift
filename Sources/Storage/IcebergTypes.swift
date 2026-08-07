//
//  IcebergTypes.swift
//  Storage
//
//  Created by Guilherme Souza on 06/08/26.
//

public import Foundation

/// An Apache Iceberg primitive or nested field type.
///
/// Use a string literal for primitive types (`"long"`, `"string"`, `"timestamp"`, etc.) or one of
/// the nested cases for `struct`, `list`, and `map` columns.
///
/// ```swift
/// IcebergStructField(id: 1, name: "id", type: "long", required: true)
/// IcebergStructField(
///   id: 2,
///   name: "tags",
///   type: .listType(elementId: 3, element: "string", elementRequired: false),
///   required: false
/// )
/// ```
///
/// - Warning: Analytics buckets are a public alpha feature of Supabase Storage and this API is
///   experimental — it may change in a breaking way, or be unavailable on your project, until it
///   reaches general availability. Opt in with `@_spi(Experimental) import Supabase`.
@_spi(Experimental)
public indirect enum IcebergType: Sendable, Hashable {
  /// A primitive type name, e.g. `"boolean"`, `"integer"`, `"long"`, `"float"`, `"double"`,
  /// `"date"`, `"time"`, `"timestamp"`, `"timestamptz"`, `"string"`, `"uuid"`, `"fixed"`, or
  /// `"binary"`.
  case primitive(String)

  /// A nested struct column composed of the given fields.
  case structType(fields: [IcebergStructField])

  /// A list column.
  case listType(elementId: Int, element: IcebergType, elementRequired: Bool)

  /// A map column.
  case mapType(keyId: Int, key: IcebergType, valueId: Int, value: IcebergType, valueRequired: Bool)
}

extension IcebergType: ExpressibleByStringLiteral {
  public init(stringLiteral value: String) {
    self = .primitive(value)
  }
}

extension IcebergType: Codable {
  private enum CodingKeys: String, CodingKey {
    case type
    case fields
    case elementId = "element-id"
    case element
    case elementRequired = "element-required"
    case keyId = "key-id"
    case key
    case valueId = "value-id"
    case value
    case valueRequired = "value-required"
  }

  public init(from decoder: any Decoder) throws {
    if let container = try? decoder.singleValueContainer(),
      let primitive = try? container.decode(String.self)
    {
      self = .primitive(primitive)
      return
    }

    let container = try decoder.container(keyedBy: CodingKeys.self)
    let type = try container.decode(String.self, forKey: .type)
    switch type {
    case "struct":
      self = .structType(fields: try container.decode([IcebergStructField].self, forKey: .fields))
    case "list":
      self = .listType(
        elementId: try container.decode(Int.self, forKey: .elementId),
        element: try container.decode(IcebergType.self, forKey: .element),
        elementRequired: try container.decode(Bool.self, forKey: .elementRequired)
      )
    case "map":
      self = .mapType(
        keyId: try container.decode(Int.self, forKey: .keyId),
        key: try container.decode(IcebergType.self, forKey: .key),
        valueId: try container.decode(Int.self, forKey: .valueId),
        value: try container.decode(IcebergType.self, forKey: .value),
        valueRequired: try container.decode(Bool.self, forKey: .valueRequired)
      )
    default:
      throw DecodingError.dataCorruptedError(
        forKey: .type, in: container, debugDescription: "Unknown Iceberg field type: \(type)")
    }
  }

  public func encode(to encoder: any Encoder) throws {
    switch self {
    case .primitive(let name):
      var container = encoder.singleValueContainer()
      try container.encode(name)
    case .structType(let fields):
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode("struct", forKey: .type)
      try container.encode(fields, forKey: .fields)
    case .listType(let elementId, let element, let elementRequired):
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode("list", forKey: .type)
      try container.encode(elementId, forKey: .elementId)
      try container.encode(element, forKey: .element)
      try container.encode(elementRequired, forKey: .elementRequired)
    case .mapType(let keyId, let key, let valueId, let value, let valueRequired):
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode("map", forKey: .type)
      try container.encode(keyId, forKey: .keyId)
      try container.encode(key, forKey: .key)
      try container.encode(valueId, forKey: .valueId)
      try container.encode(value, forKey: .value)
      try container.encode(valueRequired, forKey: .valueRequired)
    }
  }
}

/// A single field within an ``IcebergSchema`` or nested ``IcebergType/structType(fields:)``.
///
/// - Warning: Experimental. See ``IcebergType``.
@_spi(Experimental)
public struct IcebergStructField: Codable, Sendable, Hashable {
  /// The field's unique ID within the table.
  public var id: Int

  /// The field's name.
  public var name: String

  /// The field's type.
  public var type: IcebergType

  /// Whether the field is required (`NOT NULL`).
  public var required: Bool

  /// An optional human-readable description of the field.
  public var doc: String?

  /// Creates an ``IcebergStructField``.
  public init(id: Int, name: String, type: IcebergType, required: Bool, doc: String? = nil) {
    self.id = id
    self.name = name
    self.type = type
    self.required = required
    self.doc = doc
  }
}

/// An Iceberg table schema: a `struct` of top-level fields.
///
/// ```swift
/// IcebergSchema(fields: [
///   IcebergStructField(id: 1, name: "id", type: "long", required: true),
///   IcebergStructField(id: 2, name: "name", type: "string", required: false),
/// ])
/// ```
///
/// - Warning: Experimental. See ``IcebergType``.
@_spi(Experimental)
public struct IcebergSchema: Sendable, Hashable {
  /// The schema's top-level fields.
  public var fields: [IcebergStructField]

  /// The schema's identifier, assigned by the catalog.
  public var schemaId: Int?

  /// IDs of fields that make up the table's identifier (primary key).
  public var identifierFieldIds: [Int]?

  /// Creates an ``IcebergSchema``.
  public init(fields: [IcebergStructField], schemaId: Int? = nil, identifierFieldIds: [Int]? = nil)
  {
    self.fields = fields
    self.schemaId = schemaId
    self.identifierFieldIds = identifierFieldIds
  }
}

extension IcebergSchema: Codable {
  private enum CodingKeys: String, CodingKey {
    case type
    case fields
    case schemaId = "schema-id"
    case identifierFieldIds = "identifier-field-ids"
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    fields = try container.decode([IcebergStructField].self, forKey: .fields)
    schemaId = try container.decodeIfPresent(Int.self, forKey: .schemaId)
    identifierFieldIds = try container.decodeIfPresent([Int].self, forKey: .identifierFieldIds)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode("struct", forKey: .type)
    try container.encode(fields, forKey: .fields)
    try container.encodeIfPresent(schemaId, forKey: .schemaId)
    try container.encodeIfPresent(identifierFieldIds, forKey: .identifierFieldIds)
  }
}

/// A single partition field within an ``IcebergPartitionSpec``.
///
/// - Warning: Experimental. See ``IcebergType``.
@_spi(Experimental)
public struct IcebergPartitionField: Codable, Sendable, Hashable {
  /// The ID of the source field (from the table's schema) this partition field derives from.
  public var sourceId: Int

  /// The partition field's own ID, assigned by the catalog.
  public var fieldId: Int?

  /// The partition field's name.
  public var name: String

  /// The transform applied to the source field, e.g. `"identity"`, `"bucket[16]"`, `"day"`.
  public var transform: String

  private enum CodingKeys: String, CodingKey {
    case sourceId = "source-id"
    case fieldId = "field-id"
    case name
    case transform
  }

  /// Creates an ``IcebergPartitionField``.
  public init(sourceId: Int, name: String, transform: String, fieldId: Int? = nil) {
    self.sourceId = sourceId
    self.name = name
    self.transform = transform
    self.fieldId = fieldId
  }
}

/// An Iceberg table's partitioning specification.
///
/// - Warning: Experimental. See ``IcebergType``.
@_spi(Experimental)
public struct IcebergPartitionSpec: Codable, Sendable, Hashable {
  /// The partition fields, applied in order.
  public var fields: [IcebergPartitionField]

  /// The spec's identifier, assigned by the catalog.
  public var specId: Int?

  private enum CodingKeys: String, CodingKey {
    case fields
    case specId = "spec-id"
  }

  /// Creates an ``IcebergPartitionSpec``.
  public init(fields: [IcebergPartitionField], specId: Int? = nil) {
    self.fields = fields
    self.specId = specId
  }
}

/// Sort direction for an ``IcebergSortField``.
///
/// - Warning: Experimental. See ``IcebergType``.
@_spi(Experimental)
public struct IcebergSortDirection: RawRepresentable, Hashable, Sendable {
  /// The raw string value sent to the API.
  public let rawValue: String

  /// Creates an ``IcebergSortDirection`` from a raw string value.
  public init(rawValue: String) { self.rawValue = rawValue }

  /// Ascending order.
  public static let ascending = IcebergSortDirection(rawValue: "asc")

  /// Descending order.
  public static let descending = IcebergSortDirection(rawValue: "desc")
}

extension IcebergSortDirection: ExpressibleByStringLiteral {
  public init(stringLiteral value: String) { self.init(rawValue: value) }
}

extension IcebergSortDirection: Codable {
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    self.init(rawValue: try container.decode(String.self))
  }
}

/// Null ordering for an ``IcebergSortField``.
///
/// - Warning: Experimental. See ``IcebergType``.
@_spi(Experimental)
public struct IcebergNullOrder: RawRepresentable, Hashable, Sendable {
  /// The raw string value sent to the API.
  public let rawValue: String

  /// Creates an ``IcebergNullOrder`` from a raw string value.
  public init(rawValue: String) { self.rawValue = rawValue }

  /// Nulls sort before non-null values.
  public static let first = IcebergNullOrder(rawValue: "nulls-first")

  /// Nulls sort after non-null values.
  public static let last = IcebergNullOrder(rawValue: "nulls-last")
}

extension IcebergNullOrder: ExpressibleByStringLiteral {
  public init(stringLiteral value: String) { self.init(rawValue: value) }
}

extension IcebergNullOrder: Codable {
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    self.init(rawValue: try container.decode(String.self))
  }
}

/// A single field within an ``IcebergSortOrder``.
///
/// - Warning: Experimental. See ``IcebergType``.
@_spi(Experimental)
public struct IcebergSortField: Codable, Sendable, Hashable {
  /// The ID of the source field (from the table's schema) this sort field derives from.
  public var sourceId: Int

  /// The transform applied to the source field before sorting, e.g. `"identity"`.
  public var transform: String

  /// The sort direction.
  public var direction: IcebergSortDirection

  /// How `null` values are ordered.
  public var nullOrder: IcebergNullOrder

  private enum CodingKeys: String, CodingKey {
    case sourceId = "source-id"
    case transform
    case direction
    case nullOrder = "null-order"
  }

  /// Creates an ``IcebergSortField``.
  public init(
    sourceId: Int, transform: String, direction: IcebergSortDirection, nullOrder: IcebergNullOrder
  ) {
    self.sourceId = sourceId
    self.transform = transform
    self.direction = direction
    self.nullOrder = nullOrder
  }
}

/// An Iceberg table's write-order specification, used to sort data on write.
///
/// - Warning: Experimental. See ``IcebergType``.
@_spi(Experimental)
public struct IcebergSortOrder: Codable, Sendable, Hashable {
  /// The sort fields, applied in order.
  public var fields: [IcebergSortField]

  /// The order's identifier, assigned by the catalog.
  public var orderId: Int?

  private enum CodingKeys: String, CodingKey {
    case fields
    case orderId = "order-id"
  }

  /// Creates an ``IcebergSortOrder``.
  public init(fields: [IcebergSortField], orderId: Int? = nil) {
    self.fields = fields
    self.orderId = orderId
  }
}

/// An Iceberg table's metadata, as returned by ``IcebergNamespaceClient``.
///
/// - Warning: Experimental. See ``IcebergType``.
@_spi(Experimental)
public struct IcebergTableMetadata: Decodable, Sendable, Hashable {
  /// The table format version (1 or 2).
  public var formatVersion: Int

  /// A UUID that uniquely identifies the table.
  public var tableUUID: String

  /// The base location of the table's data and metadata files.
  public var location: String?

  /// When the metadata was last updated.
  public var lastUpdatedAt: TimeInterval?

  /// Arbitrary key-value table properties.
  public var properties: [String: String]?

  /// The schema history for the table.
  public var schemas: [IcebergSchema]?

  /// The ID of the current schema in ``schemas``.
  public var currentSchemaId: Int?

  /// The ID of the table's current snapshot, if any.
  public var currentSnapshotId: Int?

  /// All known partition specs for the table.
  public var partitionSpecs: [IcebergPartitionSpec]?

  /// The ID of the default partition spec in ``partitionSpecs``.
  public var defaultSpecId: Int?

  private enum CodingKeys: String, CodingKey {
    case formatVersion = "format-version"
    case tableUUID = "table-uuid"
    case location
    case lastUpdatedMs = "last-updated-ms"
    case properties
    case schemas
    case currentSchemaId = "current-schema-id"
    case currentSnapshotId = "current-snapshot-id"
    case partitionSpecs = "partition-specs"
    case defaultSpecId = "default-spec-id"
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    formatVersion = try container.decode(Int.self, forKey: .formatVersion)
    tableUUID = try container.decode(String.self, forKey: .tableUUID)
    location = try container.decodeIfPresent(String.self, forKey: .location)
    let lastUpdatedMs = try container.decodeIfPresent(Int.self, forKey: .lastUpdatedMs)
    lastUpdatedAt = lastUpdatedMs.map { TimeInterval($0) / 1000 }
    properties = try container.decodeIfPresent([String: String].self, forKey: .properties)
    schemas = try container.decodeIfPresent([IcebergSchema].self, forKey: .schemas)
    currentSchemaId = try container.decodeIfPresent(Int.self, forKey: .currentSchemaId)
    currentSnapshotId = try container.decodeIfPresent(Int.self, forKey: .currentSnapshotId)
    partitionSpecs = try container.decodeIfPresent(
      [IcebergPartitionSpec].self, forKey: .partitionSpecs)
    defaultSpecId = try container.decodeIfPresent(Int.self, forKey: .defaultSpecId)
  }
}

/// The result of creating or loading an Iceberg table, as returned by ``IcebergNamespaceClient``.
///
/// - Warning: Experimental. See ``IcebergType``.
@_spi(Experimental)
public struct IcebergLoadTableResult: Decodable, Sendable, Hashable {
  /// The location of the table's metadata file.
  public var metadataLocation: String

  /// The table's metadata.
  public var metadata: IcebergTableMetadata

  private enum CodingKeys: String, CodingKey {
    case metadataLocation = "metadata-location"
    case metadata
  }
}
