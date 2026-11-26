//
//  IcebergTableMetadata.swift
//  StorageIceberg
//
//  Created by Guilherme Souza on 25/11/26.
//

public import Foundation
public import Helpers

/// The identifier of a table in an ``IcebergCatalog``: its namespace and its name.
///
/// - Warning: Experimental. See ``IcebergCatalog``.
@_spi(Experimental)
public struct IcebergTableIdentifier: Hashable, Sendable, Decodable {
  /// The namespace that holds the table. The levels of a nested namespace are joined with `.`.
  public var namespace: String

  /// The table name.
  public var name: String

  /// Creates an ``IcebergTableIdentifier``.
  public init(namespace: String, name: String) {
    self.namespace = namespace
    self.name = name
  }

  private enum CodingKeys: String, CodingKey {
    case namespace, name
  }

  /// Decodes an identifier whose namespace is an array of levels.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    namespace = IcebergCatalog.name(of: try container.decode([String].self, forKey: .namespace))
    name = try container.decode(String.self, forKey: .name)
  }
}

/// The definition of a table to create with ``IcebergCatalog/createTable(_:in:)``.
///
/// - Warning: Experimental. See ``IcebergCatalog``.
@_spi(Experimental)
public struct IcebergTableCreation: Hashable, Sendable, Encodable {
  /// The table name.
  public var name: String

  /// The table schema.
  public var schema: IcebergSchema

  /// How the table partitions its data. `nil` creates an unpartitioned table.
  public var partitionSpec: IcebergPartitionSpec?

  /// The order in which the table sorts written data. `nil` leaves the data unsorted.
  public var writeOrder: IcebergSortOrder?

  /// The table properties.
  public var properties: [String: String]

  /// The location of the table data. `nil` lets the catalog pick it.
  public var location: String?

  /// Creates an ``IcebergTableCreation``.
  public init(
    name: String,
    schema: IcebergSchema,
    partitionSpec: IcebergPartitionSpec? = nil,
    writeOrder: IcebergSortOrder? = nil,
    properties: [String: String] = [:],
    location: String? = nil
  ) {
    self.name = name
    self.schema = schema
    self.partitionSpec = partitionSpec
    self.writeOrder = writeOrder
    self.properties = properties
    self.location = location
  }

  private enum CodingKeys: String, CodingKey {
    case name, schema
    case partitionSpec = "partition-spec"
    case writeOrder = "write-order"
    case properties, location
  }
}

/// The metadata of an Iceberg table.
///
/// The typed properties hold the common fields. ``raw`` holds the whole metadata object as the
/// catalog sent it, with numbers at their exact digits, so you can read any other field.
///
/// - Warning: Experimental. See ``IcebergCatalog``.
@_spi(Experimental)
public struct IcebergTableMetadata: Hashable, Sendable, Decodable {
  /// The Iceberg table format version, such as `2`.
  public var formatVersion: Int?

  /// The table UUID.
  public var tableUUID: String?

  /// The location of the table data.
  public var location: String?

  /// When the table last changed. The catalog sends milliseconds since the Unix epoch; the exact
  /// value is in ``raw`` under `last-updated-ms`.
  public var lastUpdated: Date?

  /// The table properties; empty when the catalog sent none.
  public var properties: [String: String]

  /// Every schema the table has had; empty when the catalog sent none.
  public var schemas: [IcebergSchema]

  /// The ID of the current schema in ``schemas``.
  public var currentSchemaID: Int?

  /// Every partition spec the table has had; empty when the catalog sent none.
  ///
  /// A spec that this type cannot read, such as one with a format v3 multi-argument transform,
  /// is left out. It stays in ``raw``.
  public var partitionSpecs: [IcebergPartitionSpec]

  /// The ID of the default partition spec in ``partitionSpecs``.
  public var defaultSpecID: Int?

  /// Every sort order the table has had; empty when the catalog sent none.
  ///
  /// A sort order that this type cannot read, such as one with a format v3 multi-argument
  /// transform, is left out. It stays in ``raw``.
  public var sortOrders: [IcebergSortOrder]

  /// The ID of the default sort order in ``sortOrders``.
  public var defaultSortOrderID: Int?

  /// The ID of the current snapshot. Some catalogs send `-1` when the table has no snapshot.
  public var currentSnapshotID: Int64?

  /// The whole metadata object as the catalog sent it.
  public var raw: JSONObject

  /// The schema in ``schemas`` whose ID is ``currentSchemaID``, if any.
  public var currentSchema: IcebergSchema? {
    guard let currentSchemaID else { return nil }
    return schemas.first { $0.schemaID == currentSchemaID }
  }

  /// Creates an ``IcebergTableMetadata``.
  public init(
    formatVersion: Int? = nil,
    tableUUID: String? = nil,
    location: String? = nil,
    lastUpdated: Date? = nil,
    properties: [String: String] = [:],
    schemas: [IcebergSchema] = [],
    currentSchemaID: Int? = nil,
    partitionSpecs: [IcebergPartitionSpec] = [],
    defaultSpecID: Int? = nil,
    sortOrders: [IcebergSortOrder] = [],
    defaultSortOrderID: Int? = nil,
    currentSnapshotID: Int64? = nil,
    raw: JSONObject = [:]
  ) {
    self.formatVersion = formatVersion
    self.tableUUID = tableUUID
    self.location = location
    self.lastUpdated = lastUpdated
    self.properties = properties
    self.schemas = schemas
    self.currentSchemaID = currentSchemaID
    self.partitionSpecs = partitionSpecs
    self.defaultSpecID = defaultSpecID
    self.sortOrders = sortOrders
    self.defaultSortOrderID = defaultSortOrderID
    self.currentSnapshotID = currentSnapshotID
    self.raw = raw
  }

  private enum CodingKeys: String, CodingKey {
    case formatVersion = "format-version"
    case tableUUID = "table-uuid"
    case location
    case lastUpdatedMilliseconds = "last-updated-ms"
    case properties, schemas
    case currentSchemaID = "current-schema-id"
    case partitionSpecs = "partition-specs"
    case defaultSpecID = "default-spec-id"
    case sortOrders = "sort-orders"
    case defaultSortOrderID = "default-sort-order-id"
    case currentSnapshotID = "current-snapshot-id"
  }

  /// Decodes the metadata and keeps the whole object in ``raw``.
  public init(from decoder: any Decoder) throws {
    raw = try decoder.singleValueContainer().decode(JSONObject.self)
    let container = try decoder.container(keyedBy: CodingKeys.self)
    formatVersion = try container.decodeIfPresent(Int.self, forKey: .formatVersion)
    tableUUID = try container.decodeIfPresent(String.self, forKey: .tableUUID)
    location = try container.decodeIfPresent(String.self, forKey: .location)
    lastUpdated = try container.decodeIfPresent(Int64.self, forKey: .lastUpdatedMilliseconds)
      .map { Date(timeIntervalSince1970: Double($0) / 1000) }
    properties =
      try container.decodeIfPresent([String: String].self, forKey: .properties) ?? [:]
    schemas = try container.decodeIfPresent([IcebergSchema].self, forKey: .schemas) ?? []
    currentSchemaID = try container.decodeIfPresent(Int.self, forKey: .currentSchemaID)
    partitionSpecs =
      try container.decodeIfPresent([Readable<IcebergPartitionSpec>].self, forKey: .partitionSpecs)?
      .compactMap(\.value) ?? []
    defaultSpecID = try container.decodeIfPresent(Int.self, forKey: .defaultSpecID)
    sortOrders =
      try container.decodeIfPresent([Readable<IcebergSortOrder>].self, forKey: .sortOrders)?
      .compactMap(\.value) ?? []
    defaultSortOrderID = try container.decodeIfPresent(Int.self, forKey: .defaultSortOrderID)
    currentSnapshotID = try container.decodeIfPresent(Int64.self, forKey: .currentSnapshotID)
  }
}

/// A table that the catalog loaded or created: its metadata and the settings to read its data.
///
/// - Warning: Experimental. See ``IcebergCatalog``.
@_spi(Experimental)
public struct IcebergLoadedTable: Hashable, Sendable, Decodable {
  /// The location of the table's current metadata file, if the catalog sent one.
  public var metadataLocation: String?

  /// The table metadata.
  public var metadata: IcebergTableMetadata

  /// The settings the catalog sent for reading the table data; empty when it sent none.
  public var config: [String: String]

  /// Creates an ``IcebergLoadedTable``.
  public init(
    metadataLocation: String? = nil,
    metadata: IcebergTableMetadata,
    config: [String: String] = [:]
  ) {
    self.metadataLocation = metadataLocation
    self.metadata = metadata
    self.config = config
  }

  private enum CodingKeys: String, CodingKey {
    case metadataLocation = "metadata-location"
    case metadata, config
  }

  /// Decodes a loaded table. A missing `config` decodes as empty.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    metadataLocation = try container.decodeIfPresent(String.self, forKey: .metadataLocation)
    metadata = try container.decode(IcebergTableMetadata.self, forKey: .metadata)
    config = try container.decodeIfPresent([String: String].self, forKey: .config) ?? [:]
  }
}

/// A table after the catalog committed a change to it.
///
/// - Warning: Experimental. See ``IcebergCatalog``.
@_spi(Experimental)
public struct IcebergCommittedTable: Hashable, Sendable, Decodable {
  /// The location of the metadata file that the commit wrote.
  public var metadataLocation: String

  /// The table metadata after the commit.
  public var metadata: IcebergTableMetadata

  /// Creates an ``IcebergCommittedTable``.
  public init(metadataLocation: String, metadata: IcebergTableMetadata) {
    self.metadataLocation = metadataLocation
    self.metadata = metadata
  }

  private enum CodingKeys: String, CodingKey {
    case metadataLocation = "metadata-location"
    case metadata
  }
}

/// A list element that decodes to `nil` when `Value` cannot read it, so one entry in a newer
/// shape does not fail the whole metadata.
private struct Readable<Value: Decodable>: Decodable {
  let value: Value?

  init(from decoder: any Decoder) throws {
    value = try? Value(from: decoder)
  }
}
