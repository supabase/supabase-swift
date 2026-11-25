//
//  IcebergTableRequirement.swift
//  StorageIceberg
//
//  Created by Guilherme Souza on 25/11/26.
//

public import Helpers

/// A condition that a table must meet for
/// ``IcebergCatalog/updateTable(_:in:requirements:updates:)`` to commit.
///
/// When a requirement fails, the catalog commits nothing and answers 409 with code
/// `CommitFailedException`.
///
/// - Warning: Experimental. See ``IcebergCatalog``.
@_spi(Experimental)
public struct IcebergTableRequirement: Hashable, Sendable, Encodable {
  /// The kind of condition, such as `assert-current-schema-id`. It is sent as `type`.
  public var kind: Kind

  /// The other fields of the condition, keyed by their wire names.
  public var fields: JSONObject

  /// A condition with any kind and fields.
  ///
  /// - Parameters:
  ///   - kind: The kind as the catalog spells it, such as `assert-create`.
  ///   - fields: The other fields, keyed by their wire names. A `type` key here is overwritten
  ///     by the discriminator.
  /// - Returns: The requirement.
  public static func custom(_ kind: Kind, fields: JSONObject = [:]) -> Self {
    Self(kind: kind, fields: fields)
  }

  /// The table must not exist yet.
  public static func assertCreate() -> Self {
    custom(.assertCreate)
  }

  /// The table UUID must match.
  ///
  /// - Parameter uuid: The expected table UUID.
  /// - Returns: The requirement.
  public static func assertTableUUID(_ uuid: String) -> Self {
    custom(.assertTableUUID, fields: ["uuid": .string(uuid)])
  }

  /// A branch or tag must point at a snapshot.
  ///
  /// - Parameters:
  ///   - ref: The branch or tag name, such as `main`.
  ///   - snapshotID: The expected snapshot ID. `nil` means the ref must not exist.
  /// - Returns: The requirement.
  public static func assertRefSnapshotID(ref: String, snapshotID: Int64?) -> Self {
    custom(
      .assertRefSnapshotID,
      fields: [
        "ref": .string(ref),
        "snapshot-id": snapshotID.map { .number(JSONNumber($0)) } ?? .null,
      ])
  }

  /// The current schema ID must match.
  ///
  /// - Parameter id: The expected current schema ID.
  /// - Returns: The requirement.
  public static func assertCurrentSchemaID(_ id: Int) -> Self {
    custom(.assertCurrentSchemaID, fields: ["current-schema-id": .number(JSONNumber(id))])
  }

  /// The highest field ID that the table has assigned must match.
  ///
  /// - Parameter id: The expected field ID.
  /// - Returns: The requirement.
  public static func assertLastAssignedFieldID(_ id: Int) -> Self {
    custom(
      .assertLastAssignedFieldID, fields: ["last-assigned-field-id": .number(JSONNumber(id))])
  }

  /// The highest partition field ID that the table has assigned must match.
  ///
  /// - Parameter id: The expected partition field ID.
  /// - Returns: The requirement.
  public static func assertLastAssignedPartitionID(_ id: Int) -> Self {
    custom(
      .assertLastAssignedPartitionID,
      fields: ["last-assigned-partition-id": .number(JSONNumber(id))])
  }

  /// The default partition spec ID must match.
  ///
  /// - Parameter id: The expected spec ID.
  /// - Returns: The requirement.
  public static func assertDefaultSpecID(_ id: Int) -> Self {
    custom(.assertDefaultSpecID, fields: ["default-spec-id": .number(JSONNumber(id))])
  }

  /// The default sort order ID must match.
  ///
  /// - Parameter id: The expected sort order ID.
  /// - Returns: The requirement.
  public static func assertDefaultSortOrderID(_ id: Int) -> Self {
    custom(
      .assertDefaultSortOrderID, fields: ["default-sort-order-id": .number(JSONNumber(id))])
  }

  /// Encodes ``fields`` with `type` set to ``kind``.
  public func encode(to encoder: any Encoder) throws {
    var object = fields
    object["type"] = .string(kind.rawValue)
    try object.encode(to: encoder)
  }
}

extension IcebergTableRequirement {
  /// The kind of an ``IcebergTableRequirement``, as the catalog spells it, such as
  /// `assert-create`.
  ///
  /// - Warning: Experimental. See ``IcebergCatalog``.
  public struct Kind: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    /// The kind as the catalog spells it.
    public let rawValue: String

    /// Creates a ``Kind`` from its name.
    public init(rawValue: String) {
      self.rawValue = rawValue
    }

    /// Creates a ``Kind`` from its name.
    public init(stringLiteral value: String) {
      self.init(rawValue: value)
    }

    /// `assert-create`: The table must not exist yet.
    public static let assertCreate: Kind = "assert-create"

    /// `assert-table-uuid`: The table UUID must match.
    public static let assertTableUUID: Kind = "assert-table-uuid"

    /// `assert-ref-snapshot-id`: A branch or tag must point at a snapshot.
    public static let assertRefSnapshotID: Kind = "assert-ref-snapshot-id"

    /// `assert-current-schema-id`: The current schema ID must match.
    public static let assertCurrentSchemaID: Kind = "assert-current-schema-id"

    /// `assert-last-assigned-field-id`: The highest assigned field ID must match.
    public static let assertLastAssignedFieldID: Kind = "assert-last-assigned-field-id"

    /// `assert-last-assigned-partition-id`: The highest assigned partition field ID must match.
    public static let assertLastAssignedPartitionID: Kind = "assert-last-assigned-partition-id"

    /// `assert-default-spec-id`: The default partition spec ID must match.
    public static let assertDefaultSpecID: Kind = "assert-default-spec-id"

    /// `assert-default-sort-order-id`: The default sort order ID must match.
    public static let assertDefaultSortOrderID: Kind = "assert-default-sort-order-id"
  }
}
