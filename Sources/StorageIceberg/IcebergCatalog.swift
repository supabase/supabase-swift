//
//  IcebergCatalog.swift
//  StorageIceberg
//
//  Created by Guilherme Souza on 25/11/26.
//

import Foundation

@_spi(Experimental) public import Storage

extension StorageAnalyticsClient {
  /// Returns a client for the Iceberg REST catalog of an analytics bucket.
  ///
  /// - Warning: Experimental. See ``IcebergCatalog``.
  ///
  /// - Parameter bucket: The name of the analytics bucket.
  /// - Returns: The catalog client. It sends no request until you call one of its methods.
  @_spi(Experimental)
  public func catalog(bucket: String) -> IcebergCatalog {
    IcebergCatalog(analytics: self, bucket: bucket)
  }
}

/// A client for the Iceberg REST catalog of one analytics bucket.
///
/// Obtain an instance with ``Storage/StorageAnalyticsClient/catalog(bucket:)``:
///
/// ```swift
/// @_spi(Experimental) import StorageIceberg
///
/// let catalog = client.storage.analytics.catalog(bucket: "events")
/// try await catalog.createNamespace("sales")
/// let namespaces = try await catalog.listNamespaces()
/// ```
///
/// Every method needs the `secret` key and throws `StorageError` when the catalog rejects the
/// request. The catalog's own error type, such as `NoSuchNamespaceException`, is in the error's
/// `code`. A cancelled task throws `CancellationError`.
///
/// - Warning: Analytics buckets are a public alpha feature of Supabase Storage and this API is
///   experimental — it may change in a breaking way, or be unavailable on your project, until it
///   reaches general availability. Opt in with `@_spi(Experimental) import StorageIceberg`.
///
/// ## Topics
///
/// ### The bucket
///
/// - ``bucket``
///
/// ### Managing namespaces
///
/// - ``createNamespace(_:properties:)``
/// - ``listNamespaces()``
/// - ``namespaceProperties(_:)``
/// - ``namespaceExists(_:)``
/// - ``deleteNamespace(_:)``
///
/// ### Managing tables
///
/// - ``createTable(_:in:)``
/// - ``listTables(in:)``
/// - ``table(_:in:)``
/// - ``updateTable(_:in:requirements:updates:)``
/// - ``tableExists(_:in:)``
/// - ``deleteTable(_:in:purge:)``
///
/// ### Namespaces
///
/// - ``IcebergNamespace``
///
/// ### Tables
///
/// - ``IcebergTableCreation``
/// - ``IcebergTableIdentifier``
/// - ``IcebergLoadedTable``
/// - ``IcebergTableMetadata``
/// - ``IcebergCommittedTable``
///
/// ### Schemas
///
/// - ``IcebergSchema``
/// - ``IcebergField``
/// - ``IcebergType``
/// - ``IcebergPrimitiveType``
/// - ``IcebergListType``
/// - ``IcebergMapType``
///
/// ### Partitioning and sorting
///
/// - ``IcebergPartitionSpec``
/// - ``IcebergPartitionField``
/// - ``IcebergTransform``
/// - ``IcebergSortOrder``
/// - ``IcebergSortField``
/// - ``IcebergSortDirection``
/// - ``IcebergNullOrder``
///
/// ### Table commits
///
/// - ``IcebergTableUpdate``
/// - ``IcebergTableRequirement``
@_spi(Experimental)
public struct IcebergCatalog: Sendable {
  let analytics: StorageAnalyticsClient

  /// The name of the analytics bucket that holds this catalog.
  ///
  /// - Warning: Experimental. See ``IcebergCatalog``.
  public let bucket: String
}

extension IcebergCatalog {
  /// Creates a table in a namespace.
  ///
  /// - Warning: Experimental. See ``IcebergCatalog``.
  ///
  /// - Parameters:
  ///   - table: The table definition.
  ///   - namespace: The namespace that holds the table.
  /// - Returns: The created table.
  /// - Throws: `StorageError` when the catalog rejects the request, e.g. with code
  ///   `AlreadyExistsException` when the table exists, or `NoSuchNamespaceException` when the
  ///   namespace does not exist.
  @_spi(Experimental)
  @discardableResult
  public func createTable(_ table: IcebergTableCreation, in namespace: String) async throws
    -> IcebergLoadedTable
  {
    try await send(.post, path: ["namespaces", namespace, "tables"], body: table)
  }

  /// Lists the tables in a namespace.
  ///
  /// - Warning: Experimental. See ``IcebergCatalog``.
  ///
  /// - Parameter namespace: The namespace name.
  /// - Returns: The identifiers of the tables in the namespace.
  /// - Throws: `StorageError` when the catalog rejects the request, e.g. with code
  ///   `NoSuchNamespaceException` when the namespace does not exist.
  @_spi(Experimental)
  public func listTables(in namespace: String) async throws -> [IcebergTableIdentifier] {
    let response: ListTablesResponse = try await send(
      .get, path: ["namespaces", namespace, "tables"])
    return response.identifiers ?? []
  }

  /// Loads a table.
  ///
  /// - Warning: Experimental. See ``IcebergCatalog``.
  ///
  /// - Parameters:
  ///   - name: The table name.
  ///   - namespace: The namespace that holds the table.
  /// - Returns: The table metadata and the settings to read its data.
  /// - Throws: `StorageError` when the catalog rejects the request, e.g. with code
  ///   `NoSuchTableException` when the table does not exist.
  @_spi(Experimental)
  public func table(_ name: String, in namespace: String) async throws -> IcebergLoadedTable {
    try await send(.get, path: ["namespaces", namespace, "tables", name])
  }

  /// Commits changes to a table.
  ///
  /// The catalog checks every requirement, then applies every update, as one atomic commit:
  ///
  /// ```swift
  /// try await catalog.updateTable(
  ///   "orders", in: "sales",
  ///   requirements: [.assertCurrentSchemaID(0)],
  ///   updates: [.setProperties(["write.parquet.compression-codec": "zstd"])]
  /// )
  /// ```
  ///
  /// - Warning: Experimental. See ``IcebergCatalog``.
  ///
  /// - Parameters:
  ///   - name: The table name.
  ///   - namespace: The namespace that holds the table.
  ///   - requirements: The conditions the table must meet for the commit. Defaults to none.
  ///   - updates: The changes to apply, in order.
  /// - Returns: The table after the commit.
  /// - Throws: `StorageError` when the catalog rejects the request, e.g. with code
  ///   `CommitFailedException` when a requirement fails, or `NoSuchTableException` when the
  ///   table does not exist.
  @_spi(Experimental)
  @discardableResult
  public func updateTable(
    _ name: String,
    in namespace: String,
    requirements: [IcebergTableRequirement] = [],
    updates: [IcebergTableUpdate]
  ) async throws -> IcebergCommittedTable {
    try await send(
      .post, path: ["namespaces", namespace, "tables", name],
      body: CommitTableRequest(requirements: requirements, updates: updates))
  }

  /// Checks whether a table exists.
  ///
  /// - Warning: Experimental. See ``IcebergCatalog``.
  ///
  /// - Parameters:
  ///   - name: The table name.
  ///   - namespace: The namespace that holds the table.
  /// - Returns: `true` when the table exists, `false` when the catalog answers 404. The catalog
  ///   also answers 404 when the namespace or the bucket does not exist, or the project has no
  ///   Iceberg catalog, and the answer has no body, so these cases also return `false`.
  /// - Throws: `StorageError` when the catalog rejects the request for another reason.
  @_spi(Experimental)
  public func tableExists(_ name: String, in namespace: String) async throws -> Bool {
    try await exists(path: ["namespaces", namespace, "tables", name])
  }

  /// Deletes a table.
  ///
  /// - Warning: Experimental. See ``IcebergCatalog``.
  ///
  /// - Parameters:
  ///   - name: The table name.
  ///   - namespace: The namespace that holds the table.
  ///   - purge: Whether the catalog also deletes the table data and metadata files. Defaults to
  ///     `false`, which removes the table from the catalog only.
  /// - Throws: `StorageError` when the catalog rejects the request, e.g. with code
  ///   `NoSuchTableException` when the table does not exist.
  @_spi(Experimental)
  public func deleteTable(_ name: String, in namespace: String, purge: Bool = false) async throws {
    try await sendIgnoringBody(
      .delete, path: ["namespaces", namespace, "tables", name],
      query: [URLQueryItem(name: "purgeRequested", value: String(purge))])
  }
}

private struct ListTablesResponse: Decodable {
  let identifiers: [IcebergTableIdentifier]?
}

private struct CommitTableRequest: Encodable {
  let requirements: [IcebergTableRequirement]
  let updates: [IcebergTableUpdate]
}
