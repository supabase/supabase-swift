//
//  IcebergNamespaceClient.swift
//  Storage
//
//  Created by Guilherme Souza on 06/08/26.
//

import Foundation
import HTTPTypes

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// A client scoped to a single Iceberg namespace, for managing its tables.
///
/// Obtain an instance via ``AnalyticsBucketClient/namespace(_:)``:
///
/// ```swift
/// let namespace = client.storage.analytics.from("events").namespace("default")
///
/// try await namespace.createTable(
///   "clicks",
///   schema: IcebergSchema(fields: [
///     IcebergStructField(id: 1, name: "id", type: "long", required: true),
///     IcebergStructField(id: 2, name: "url", type: "string", required: false),
///   ])
/// )
/// ```
///
/// - Warning: Analytics buckets are a public alpha feature of Supabase Storage and this API is
///   experimental — it may change in a breaking way, or be unavailable on your project, until it
///   reaches general availability. Opt in with `@_spi(Experimental) import Supabase`.
///
/// ## Topics
///
/// ### Managing tables
///
/// - ``createTable(_:schema:location:partitionSpec:properties:writeOrder:stageCreate:)``
/// - ``getTable(_:)``
/// - ``listTables(pageToken:pageSize:)``
/// - ``tableExists(_:)``
/// - ``deleteTable(_:purge:)``
@_spi(Experimental)
public class IcebergNamespaceClient: StorageApi, @unchecked Sendable {
  /// The name of the analytics bucket containing ``namespaceName``.
  public let bucketName: String

  /// The name of the namespace this client operates on.
  public let namespaceName: String

  init(bucketName: String, namespaceName: String, configuration: StorageClientConfiguration) {
    self.bucketName = bucketName
    self.namespaceName = namespaceName
    super.init(configuration: configuration)
  }

  /// Creates a new Iceberg table in this namespace.
  ///
  /// ```swift
  /// try await namespace.createTable(
  ///   "clicks",
  ///   schema: IcebergSchema(fields: [
  ///     IcebergStructField(id: 1, name: "id", type: "long", required: true),
  ///     IcebergStructField(id: 2, name: "clicked_at", type: "timestamptz", required: true),
  ///   ]),
  ///   partitionSpec: IcebergPartitionSpec(fields: [
  ///     IcebergPartitionField(sourceId: 2, name: "clicked_at_day", transform: "day")
  ///   ])
  /// )
  /// ```
  ///
  /// - Warning: Experimental. See ``AnalyticsClient``.
  ///
  /// - Parameters:
  ///   - name: The name of the table to create.
  ///   - schema: The table's schema.
  ///   - location: An optional URI where the table's metadata and data will live. Defaults to a
  ///     location managed by the catalog.
  ///   - partitionSpec: An optional partitioning specification for the table.
  ///   - properties: Arbitrary key-value properties to set on the table.
  ///   - writeOrder: An optional sort order applied to writes.
  ///   - stageCreate: When `true`, initializes table metadata for a create transaction instead of
  ///     committing immediately. Defaults to `false`.
  /// - Returns: The newly created table's metadata.
  /// - Throws: ``StorageError`` when the API rejects the request.
  public func createTable(
    _ name: String,
    schema: IcebergSchema,
    location: String? = nil,
    partitionSpec: IcebergPartitionSpec? = nil,
    properties: [String: String]? = nil,
    writeOrder: IcebergSortOrder? = nil,
    stageCreate: Bool = false
  ) async throws -> IcebergLoadTableResult {
    try await execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent(
          "iceberg/v1/\(bucketName)/namespaces/\(namespaceName)/tables"),
        method: .post,
        body: JSONEncoder.unconfiguredEncoder.encode(
          CreateTableBody(
            name: name,
            location: location,
            schema: schema,
            spec: partitionSpec,
            properties: properties,
            stageCreate: stageCreate,
            writeOrder: writeOrder
          )
        )
      )
    )
    .decoded(decoder: .supabase())
  }

  /// Loads the metadata of an existing table.
  ///
  /// ```swift
  /// let table = try await namespace.getTable("clicks")
  /// print(table.metadata.location)
  /// ```
  ///
  /// - Warning: Experimental. See ``AnalyticsClient``.
  ///
  /// - Parameter name: The name of the table to load.
  /// - Returns: The table's metadata.
  /// - Throws: ``StorageError`` when the API rejects the request.
  public func getTable(_ name: String) async throws -> IcebergLoadTableResult {
    try await execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent(
          "iceberg/v1/\(bucketName)/namespaces/\(namespaceName)/tables/\(name)"),
        method: .get
      )
    )
    .decoded(decoder: .supabase())
  }

  /// Lists the tables in this namespace.
  ///
  /// Results are paginated: pass the ``ListIcebergTablesResponse/nextPageToken`` of a previous
  /// response as `pageToken` to fetch the following page.
  ///
  /// ```swift
  /// let page = try await namespace.listTables()
  /// for table in page.tables {
  ///   print(table)
  /// }
  /// ```
  ///
  /// - Warning: Experimental. See ``AnalyticsClient``.
  ///
  /// - Parameters:
  ///   - pageToken: The pagination token from a previous response.
  ///   - pageSize: The maximum number of tables to return in this page.
  /// - Returns: A page of table names, plus the token for the next page when more results exist.
  /// - Throws: ``StorageError`` when the API rejects the request.
  public func listTables(
    pageToken: String? = nil,
    pageSize: Int? = nil
  ) async throws -> ListIcebergTablesResponse {
    var query: [URLQueryItem] = []
    if let pageToken { query.append(URLQueryItem(name: "pageToken", value: pageToken)) }
    if let pageSize { query.append(URLQueryItem(name: "pageSize", value: String(pageSize))) }

    let response: ListTablesResponseBody = try await execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent(
          "iceberg/v1/\(bucketName)/namespaces/\(namespaceName)/tables"),
        method: .get,
        query: query
      )
    )
    .decoded(decoder: .supabase())
    return ListIcebergTablesResponse(
      tables: response.identifiers.map(\.name),
      nextPageToken: response.nextPageToken
    )
  }

  /// Checks whether a table exists in this namespace.
  ///
  /// ```swift
  /// if try await namespace.tableExists("clicks") {
  ///   // ...
  /// }
  /// ```
  ///
  /// - Warning: Experimental. See ``AnalyticsClient``.
  ///
  /// - Parameter name: The name of the table to check.
  /// - Returns: `true` if the table exists, `false` otherwise.
  /// - Throws: ``StorageError`` for any failure other than the table not existing.
  public func tableExists(_ name: String) async throws -> Bool {
    do {
      try await execute(
        HTTPRequest(
          url: configuration.url.appendingPathComponent(
            "iceberg/v1/\(bucketName)/namespaces/\(namespaceName)/tables/\(name)"),
          method: .head
        )
      )
      return true
    } catch let error as StorageError {
      if let statusCode = error.statusCode.flatMap(Int.init), [400, 404].contains(statusCode) {
        return false
      }
      throw error
    }
  }

  /// Deletes a table.
  ///
  /// ```swift
  /// try await namespace.deleteTable("clicks", purge: true)
  /// ```
  ///
  /// - Warning: Experimental. See ``AnalyticsClient``.
  ///
  /// - Parameters:
  ///   - name: The name of the table to delete.
  ///   - purge: When `true`, permanently deletes the table's underlying data. When `false`
  ///     (the default), the table is dropped from the catalog but its data is retained.
  /// - Throws: ``StorageError`` when the API rejects the request.
  public func deleteTable(_ name: String, purge: Bool = false) async throws {
    try await execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent(
          "iceberg/v1/\(bucketName)/namespaces/\(namespaceName)/tables/\(name)"),
        method: .delete,
        query: [URLQueryItem(name: "purgeRequested", value: purge ? "true" : "false")]
      )
    )
  }
}

private struct CreateTableBody: Encodable {
  var name: String
  var location: String?
  var schema: IcebergSchema
  var spec: IcebergPartitionSpec?
  var properties: [String: String]?
  var stageCreate: Bool
  var writeOrder: IcebergSortOrder?

  private enum CodingKeys: String, CodingKey {
    case name
    case location
    case schema
    case spec
    case properties
    case stageCreate = "stage-create"
    case writeOrder = "write-order"
  }
}

private struct ListTablesResponseBody: Decodable {
  var identifiers: [IcebergTableIdentifierBody]
  var nextPageToken: String?

  private enum CodingKeys: String, CodingKey {
    case identifiers
    case nextPageToken = "next-page-token"
  }
}

private struct IcebergTableIdentifierBody: Decodable {
  var name: String
  var namespace: [String]
}

/// A page of table names, as returned by
/// ``IcebergNamespaceClient/listTables(pageToken:pageSize:)``.
///
/// - Warning: Experimental. See ``AnalyticsClient``.
@_spi(Experimental)
public struct ListIcebergTablesResponse: Sendable {
  /// The table names in this page.
  public var tables: [String]

  /// The pagination token to pass to fetch the next page, or `nil` when there are no more results.
  public var nextPageToken: String?
}
