//
//  IcebergPartitionSpec.swift
//  StorageIceberg
//
//  Created by Guilherme Souza on 25/11/26.
//

/// How an Iceberg table splits its rows into partitions.
///
/// - Warning: Experimental. See ``IcebergCatalog``.
@_spi(Experimental)
public struct IcebergPartitionSpec: Codable, Hashable, Sendable {
  /// The partition spec ID.
  public var specID: Int

  /// The partition fields. An empty list means the table is not partitioned.
  public var fields: [IcebergPartitionField]

  /// Creates an ``IcebergPartitionSpec``.
  public init(specID: Int, fields: [IcebergPartitionField]) {
    self.specID = specID
    self.fields = fields
  }

  private enum CodingKeys: String, CodingKey {
    case specID = "spec-id"
    case fields
  }
}

/// A partition field: a transform of one source field.
///
/// - Warning: Experimental. See ``IcebergCatalog``.
@_spi(Experimental)
public struct IcebergPartitionField: Codable, Hashable, Sendable {
  /// The partition field ID. The catalog assigns it when you leave it `nil`.
  public var fieldID: Int?

  /// The ID of the schema field the partition reads.
  public var sourceID: Int

  /// The partition field name.
  public var name: String

  /// The transform applied to the source field.
  public var transform: IcebergTransform

  /// Creates an ``IcebergPartitionField``.
  public init(fieldID: Int? = nil, sourceID: Int, name: String, transform: IcebergTransform) {
    self.fieldID = fieldID
    self.sourceID = sourceID
    self.name = name
    self.transform = transform
  }

  private enum CodingKeys: String, CodingKey {
    case fieldID = "field-id"
    case sourceID = "source-id"
    case name, transform
  }
}

/// An Iceberg transform, such as `identity`, `day`, or `bucket[16]`.
///
/// - Warning: Experimental. See ``IcebergCatalog``.
@_spi(Experimental)
public struct IcebergTransform: RawRepresentable, Codable, Hashable, Sendable,
  ExpressibleByStringLiteral
{
  /// The transform as the catalog spells it.
  public let rawValue: String

  /// Creates an ``IcebergTransform`` from its name.
  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// Creates an ``IcebergTransform`` from its name.
  public init(stringLiteral value: String) {
    self.init(rawValue: value)
  }

  /// `identity`: the source value, unchanged.
  public static let identity: IcebergTransform = "identity"
  /// `year`: the year of a date or timestamp.
  public static let year: IcebergTransform = "year"
  /// `month`: the month of a date or timestamp.
  public static let month: IcebergTransform = "month"
  /// `day`: the day of a date or timestamp.
  public static let day: IcebergTransform = "day"
  /// `hour`: the hour of a timestamp.
  public static let hour: IcebergTransform = "hour"
  /// `void`: always null.
  public static let void: IcebergTransform = "void"

  /// `bucket[N]`: a hash of the source value, modulo `count`.
  ///
  /// - Parameter count: The number of buckets.
  /// - Returns: The transform.
  public static func bucket(_ count: Int) -> IcebergTransform {
    IcebergTransform(rawValue: "bucket[\(count)]")
  }

  /// `truncate[W]`: the source value truncated to `width`.
  ///
  /// - Parameter width: The truncation width.
  /// - Returns: The transform.
  public static func truncate(_ width: Int) -> IcebergTransform {
    IcebergTransform(rawValue: "truncate[\(width)]")
  }
}
