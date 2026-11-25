//
//  IcebergSortOrder.swift
//  StorageIceberg
//
//  Created by Guilherme Souza on 25/11/26.
//

/// How an Iceberg table sorts the rows in its data files.
///
/// - Warning: Experimental. See ``IcebergCatalog``.
@_spi(Experimental)
public struct IcebergSortOrder: Codable, Hashable, Sendable {
  /// The sort order ID. Order `0` with no fields means the table is not sorted.
  public var orderID: Int

  /// The sort fields, in sort priority.
  public var fields: [IcebergSortField]

  /// Creates an ``IcebergSortOrder``.
  public init(orderID: Int, fields: [IcebergSortField]) {
    self.orderID = orderID
    self.fields = fields
  }

  private enum CodingKeys: String, CodingKey {
    case orderID = "order-id"
    case fields
  }
}

/// A sort field: a transform of one source field, with a direction and a null order.
///
/// - Warning: Experimental. See ``IcebergCatalog``.
@_spi(Experimental)
public struct IcebergSortField: Codable, Hashable, Sendable {
  /// The ID of the schema field the sort reads.
  public var sourceID: Int

  /// The transform applied to the source field.
  public var transform: IcebergTransform

  /// The sort direction.
  public var direction: IcebergSortDirection

  /// Where null values sort.
  public var nullOrder: IcebergNullOrder

  /// Creates an ``IcebergSortField``.
  public init(
    sourceID: Int,
    transform: IcebergTransform,
    direction: IcebergSortDirection,
    nullOrder: IcebergNullOrder
  ) {
    self.sourceID = sourceID
    self.transform = transform
    self.direction = direction
    self.nullOrder = nullOrder
  }

  private enum CodingKeys: String, CodingKey {
    case sourceID = "source-id"
    case transform, direction
    case nullOrder = "null-order"
  }
}

/// The direction of an Iceberg sort field.
///
/// - Warning: Experimental. See ``IcebergCatalog``.
@_spi(Experimental)
public struct IcebergSortDirection: RawRepresentable, Codable, Hashable, Sendable,
  ExpressibleByStringLiteral
{
  /// The direction as the catalog spells it.
  public let rawValue: String

  /// Creates an ``IcebergSortDirection`` from its name.
  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// Creates an ``IcebergSortDirection`` from its name.
  public init(stringLiteral value: String) {
    self.init(rawValue: value)
  }

  /// `asc`: smallest value first.
  public static let ascending: IcebergSortDirection = "asc"
  /// `desc`: largest value first.
  public static let descending: IcebergSortDirection = "desc"
}

/// Where null values sort in an Iceberg sort field.
///
/// - Warning: Experimental. See ``IcebergCatalog``.
@_spi(Experimental)
public struct IcebergNullOrder: RawRepresentable, Codable, Hashable, Sendable,
  ExpressibleByStringLiteral
{
  /// The null order as the catalog spells it.
  public let rawValue: String

  /// Creates an ``IcebergNullOrder`` from its name.
  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// Creates an ``IcebergNullOrder`` from its name.
  public init(stringLiteral value: String) {
    self.init(rawValue: value)
  }

  /// `nulls-first`: null values sort before all other values.
  public static let nullsFirst: IcebergNullOrder = "nulls-first"
  /// `nulls-last`: null values sort after all other values.
  public static let nullsLast: IcebergNullOrder = "nulls-last"
}
