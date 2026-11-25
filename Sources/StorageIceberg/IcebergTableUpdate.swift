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
  public static func custom(_ action: Action, fields: JSONObject = [:]) -> Self {
    Self(action: action, fields: fields)
  }

  /// Sets the table UUID.
  ///
  /// - Parameter uuid: The new UUID.
  public static func assignUUID(_ uuid: String) -> Self {
    custom("assign-uuid", fields: ["uuid": .string(uuid)])
  }

  /// Upgrades the table to a newer Iceberg format version.
  ///
  /// - Parameter formatVersion: The format version, such as `3`.
  public static func upgradeFormatVersion(to formatVersion: Int) -> Self {
    custom("upgrade-format-version", fields: ["format-version": .number(JSONNumber(formatVersion))])
  }

  /// Adds a schema to the table. It does not become the current schema.
  ///
  /// - Parameters:
  ///   - schema: The schema to add.
  ///   - lastColumnID: The highest field ID that the table has assigned. `nil` lets the catalog
  ///     compute it.
  /// - Throws: `StorageError` with kind `invalidRequest` when `schema` cannot be encoded as
  ///   JSON, e.g. when it holds a number that no Swift number type holds exactly.
  public static func addSchema(_ schema: IcebergSchema, lastColumnID: Int? = nil) throws -> Self {
    var fields: JSONObject = ["schema": try jsonValue(of: schema)]
    if let lastColumnID {
      fields["last-column-id"] = .number(JSONNumber(lastColumnID))
    }
    return custom("add-schema", fields: fields)
  }

  /// Makes a schema of the table the current schema.
  ///
  /// - Parameter id: The schema ID. `-1` means the schema that this commit last added.
  public static func setCurrentSchema(id: Int) -> Self {
    custom("set-current-schema", fields: ["schema-id": .number(JSONNumber(id))])
  }

  /// Adds a partition spec to the table. It does not become the default spec.
  ///
  /// - Parameter spec: The partition spec to add.
  /// - Throws: `StorageError` with kind `invalidRequest` when `spec` cannot be encoded as JSON.
  public static func addPartitionSpec(_ spec: IcebergPartitionSpec) throws -> Self {
    custom("add-spec", fields: ["spec": try jsonValue(of: spec)])
  }

  /// Makes a partition spec of the table the default spec.
  ///
  /// - Parameter id: The spec ID. `-1` means the spec that this commit last added.
  public static func setDefaultPartitionSpec(id: Int) -> Self {
    custom("set-default-spec", fields: ["spec-id": .number(JSONNumber(id))])
  }

  /// Adds a sort order to the table. It does not become the default sort order.
  ///
  /// - Parameter sortOrder: The sort order to add.
  /// - Throws: `StorageError` with kind `invalidRequest` when `sortOrder` cannot be encoded as
  ///   JSON.
  public static func addSortOrder(_ sortOrder: IcebergSortOrder) throws -> Self {
    custom("add-sort-order", fields: ["sort-order": try jsonValue(of: sortOrder)])
  }

  /// Makes a sort order of the table the default sort order.
  ///
  /// - Parameter id: The sort order ID. `-1` means the sort order that this commit last added.
  public static func setDefaultSortOrder(id: Int) -> Self {
    custom("set-default-sort-order", fields: ["sort-order-id": .number(JSONNumber(id))])
  }

  /// Sets the location of the table data.
  ///
  /// - Parameter location: The new location.
  public static func setLocation(_ location: String) -> Self {
    custom("set-location", fields: ["location": .string(location)])
  }

  /// Adds or replaces table properties.
  ///
  /// - Parameter properties: The properties to set.
  public static func setProperties(_ properties: [String: String]) -> Self {
    custom("set-properties", fields: ["updates": .object(properties.mapValues(JSONValue.string))])
  }

  /// Removes table properties.
  ///
  /// - Parameter keys: The keys of the properties to remove.
  public static func removeProperties(_ keys: [String]) -> Self {
    custom("remove-properties", fields: ["removals": .array(keys.map(JSONValue.string))])
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
