//
//  IcebergTableUpdate.swift
//  StorageIceberg
//
//  Created by Guilherme Souza on 25/11/26.
//

public import Helpers

@_spi(Experimental) import Storage

/// A change to apply to a table with ``IcebergCatalog/updateTable(_:in:requirements:updates:)``.
///
/// Use a factory such as ``setProperties(_:)`` for a common change, or ``custom(_:fields:)`` for
/// any other action the catalog accepts.
///
/// - Warning: Experimental. See ``IcebergCatalog``.
@_spi(Experimental)
public struct IcebergTableUpdate: Hashable, Sendable, Encodable {
  /// The kind of change, such as `set-properties`.
  public var action: Action

  /// The other fields of the change, keyed by their wire names.
  public var fields: JSONObject

  /// A change with any action and fields.
  ///
  /// - Parameters:
  ///   - action: The action as the catalog spells it, such as `add-snapshot`.
  ///   - fields: The other fields, keyed by their wire names. An `action` key here is
  ///     overwritten by the discriminator.
  /// - Returns: The update.
  public static func custom(_ action: Action, fields: JSONObject = [:]) -> Self {
    Self(action: action, fields: fields)
  }

  /// Sets the table UUID.
  ///
  /// - Parameter uuid: The new UUID.
  /// - Returns: The update.
  public static func assignUUID(_ uuid: String) -> Self {
    custom(.assignUUID, fields: ["uuid": .string(uuid)])
  }

  /// Upgrades the table to a newer Iceberg format version.
  ///
  /// - Parameter formatVersion: The format version, such as `3`.
  /// - Returns: The update.
  public static func upgradeFormatVersion(to formatVersion: Int) -> Self {
    custom(.upgradeFormatVersion, fields: ["format-version": .number(JSONNumber(formatVersion))])
  }

  /// Adds a schema to the table. It does not become the current schema.
  ///
  /// - Important: ``IcebergField`` keeps only the keys it models. When you send back a schema
  ///   that you decoded from ``IcebergTableMetadata``, other field keys, such as the format v3
  ///   `initial-default` and `write-default`, are not sent.
  ///
  /// - Parameters:
  ///   - schema: The schema to add.
  ///   - lastColumnID: The highest field ID that the table has assigned. `nil` lets the catalog
  ///     compute it.
  /// - Returns: The update.
  /// - Throws: `StorageError` with kind `invalidRequest` when `schema` cannot be encoded as
  ///   JSON, e.g. when it holds a number that no Swift number type holds exactly.
  public static func addSchema(_ schema: IcebergSchema, lastColumnID: Int? = nil) throws -> Self {
    var fields: JSONObject = ["schema": try jsonValue(of: schema)]
    if let lastColumnID {
      fields["last-column-id"] = .number(JSONNumber(lastColumnID))
    }
    return custom(.addSchema, fields: fields)
  }

  /// Makes a schema of the table the current schema.
  ///
  /// - Parameter id: The schema ID. `-1` means the schema that this commit last added.
  /// - Returns: The update.
  public static func setCurrentSchema(id: Int) -> Self {
    custom(.setCurrentSchema, fields: ["schema-id": .number(JSONNumber(id))])
  }

  /// Adds a partition spec to the table. It does not become the default spec.
  ///
  /// - Parameter spec: The partition spec to add.
  /// - Returns: The update.
  /// - Throws: `StorageError` with kind `invalidRequest` when `spec` cannot be encoded as JSON.
  public static func addPartitionSpec(_ spec: IcebergPartitionSpec) throws -> Self {
    custom(.addPartitionSpec, fields: ["spec": try jsonValue(of: spec)])
  }

  /// Makes a partition spec of the table the default spec.
  ///
  /// - Parameter id: The spec ID. `-1` means the spec that this commit last added.
  /// - Returns: The update.
  public static func setDefaultPartitionSpec(id: Int) -> Self {
    custom(.setDefaultPartitionSpec, fields: ["spec-id": .number(JSONNumber(id))])
  }

  /// Adds a sort order to the table. It does not become the default sort order.
  ///
  /// - Parameter sortOrder: The sort order to add.
  /// - Returns: The update.
  /// - Throws: `StorageError` with kind `invalidRequest` when `sortOrder` cannot be encoded as
  ///   JSON.
  public static func addSortOrder(_ sortOrder: IcebergSortOrder) throws -> Self {
    custom(.addSortOrder, fields: ["sort-order": try jsonValue(of: sortOrder)])
  }

  /// Makes a sort order of the table the default sort order.
  ///
  /// - Parameter id: The sort order ID. `-1` means the sort order that this commit last added.
  /// - Returns: The update.
  public static func setDefaultSortOrder(id: Int) -> Self {
    custom(.setDefaultSortOrder, fields: ["sort-order-id": .number(JSONNumber(id))])
  }

  /// Sets the location of the table data.
  ///
  /// - Parameter location: The new location.
  /// - Returns: The update.
  public static func setLocation(_ location: String) -> Self {
    custom(.setLocation, fields: ["location": .string(location)])
  }

  /// Adds or replaces table properties.
  ///
  /// - Parameter properties: The properties to set.
  /// - Returns: The update.
  public static func setProperties(_ properties: [String: String]) -> Self {
    custom(.setProperties, fields: ["updates": .object(properties.mapValues(JSONValue.string))])
  }

  /// Removes table properties.
  ///
  /// - Parameter keys: The keys of the properties to remove.
  /// - Returns: The update.
  public static func removeProperties(_ keys: [String]) -> Self {
    custom(.removeProperties, fields: ["removals": .array(keys.map(JSONValue.string))])
  }

  /// Encodes ``fields`` with `action` set to ``action``.
  public func encode(to encoder: any Encoder) throws {
    var object = fields
    object["action"] = .string(action.rawValue)
    try object.encode(to: encoder)
  }
}

extension IcebergTableUpdate {
  /// The kind of an ``IcebergTableUpdate``, as the catalog spells it, such as `set-properties`.
  ///
  /// - Warning: Experimental. See ``IcebergCatalog``.
  public struct Action: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    /// The action as the catalog spells it.
    public let rawValue: String

    /// Creates an ``Action`` from its name.
    public init(rawValue: String) {
      self.rawValue = rawValue
    }

    /// Creates an ``Action`` from its name.
    public init(stringLiteral value: String) {
      self.init(rawValue: value)
    }

    /// `assign-uuid`: Sets the table UUID.
    public static let assignUUID: Action = "assign-uuid"

    /// `upgrade-format-version`: Upgrades the table format version.
    public static let upgradeFormatVersion: Action = "upgrade-format-version"

    /// `add-schema`: Adds a schema.
    public static let addSchema: Action = "add-schema"

    /// `set-current-schema`: Sets the current schema.
    public static let setCurrentSchema: Action = "set-current-schema"

    /// `add-spec`: Adds a partition spec.
    public static let addPartitionSpec: Action = "add-spec"

    /// `set-default-spec`: Sets the default partition spec.
    public static let setDefaultPartitionSpec: Action = "set-default-spec"

    /// `add-sort-order`: Adds a sort order.
    public static let addSortOrder: Action = "add-sort-order"

    /// `set-default-sort-order`: Sets the default sort order.
    public static let setDefaultSortOrder: Action = "set-default-sort-order"

    /// `set-location`: Sets the table location.
    public static let setLocation: Action = "set-location"

    /// `set-properties`: Adds or replaces table properties.
    public static let setProperties: Action = "set-properties"

    /// `remove-properties`: Removes table properties.
    public static let removeProperties: Action = "remove-properties"
  }
}

/// The JSON form of an Iceberg model.
private func jsonValue<Value: Encodable>(of value: Value) throws -> JSONValue {
  do {
    return try JSONValue(value)
  } catch {
    throw StorageError(
      kind: .invalidRequest,
      message: "The Iceberg table update cannot encode \(Value.self) as JSON.",
      underlyingError: error)
  }
}
