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
/// ### Managing namespaces
///
/// - ``createNamespace(_:properties:)``
/// - ``listNamespaces()``
/// - ``namespaceProperties(_:)``
/// - ``namespaceExists(_:)``
/// - ``deleteNamespace(_:)``
/// - ``IcebergNamespace``
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

  /// Checks whether a table exists.
  ///
  /// - Warning: Experimental. See ``IcebergCatalog``.
  ///
  /// - Parameters:
  ///   - name: The table name.
  ///   - namespace: The namespace that holds the table.
  /// - Returns: `true` when the table exists, `false` when the catalog answers 404, also when
  ///   the namespace does not exist.
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
