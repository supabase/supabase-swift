//
//  AnalyticsClient.swift
//  Storage
//
//  Created by Guilherme Souza on 06/08/26.
//

public import Foundation
import HTTPTypes

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// A client for managing Supabase Storage's alpha "analytics buckets" feature
/// (`storage.analytics`) — Iceberg-backed buckets optimized for analytical queries.
///
/// Obtain an instance via ``SupabaseStorageClient/analytics``:
///
/// ```swift
/// try await client.storage.analytics.createBucket("events")
/// let buckets = try await client.storage.analytics.listBuckets()
/// ```
///
/// - Warning: Analytics buckets are a public alpha feature of Supabase Storage and this API is
///   experimental — it may change in a breaking way, or be unavailable on your project, until it
///   reaches general availability. Opt in with `@_spi(Experimental) import Supabase`.
///
/// ## Topics
///
/// ### Managing analytics buckets
///
/// - ``createBucket(_:)``
/// - ``listBuckets(limit:offset:sortColumn:sortOrder:search:)``
/// - ``deleteBucket(_:)``
///
/// ### Managing namespaces and tables
///
/// - ``from(_:)``
@_spi(Experimental)
public struct AnalyticsClient: Sendable {
  private let api: StorageApi

  init(api: StorageApi) {
    self.api = api
  }

  /// Creates a new analytics bucket.
  ///
  /// ```swift
  /// let bucket = try await client.storage.analytics.createBucket("events")
  /// ```
  ///
  /// - Warning: Experimental. See ``AnalyticsClient``.
  ///
  /// - Parameter name: A unique name for the bucket.
  /// - Returns: The newly created ``AnalyticBucket``.
  /// - Throws: ``StorageError`` when the API rejects the request.
  public func createBucket(_ name: String) async throws -> AnalyticBucket {
    try await api.execute(
      HTTPRequest(
        url: api.configuration.url.appendingPathComponent("iceberg/bucket"),
        method: .post,
        body: JSONEncoder.unconfiguredEncoder.encode(CreateAnalyticBucketBody(name: name))
      )
    )
    .decoded(decoder: .supabase())
  }

  /// Lists the analytics buckets in the project.
  ///
  /// ```swift
  /// let buckets = try await client.storage.analytics.listBuckets(
  ///   sortColumn: .createdAt,
  ///   sortOrder: .descending
  /// )
  /// ```
  ///
  /// - Warning: Experimental. See ``AnalyticsClient``.
  ///
  /// - Parameters:
  ///   - limit: The maximum number of buckets to return.
  ///   - offset: The number of buckets to skip, for pagination.
  ///   - sortColumn: The column to sort results by.
  ///   - sortOrder: The sort direction.
  ///   - search: A search term to filter bucket names by.
  /// - Returns: The matching analytics buckets.
  /// - Throws: ``StorageError`` when the API rejects the request.
  public func listBuckets(
    limit: Int? = nil,
    offset: Int? = nil,
    sortColumn: AnalyticsBucketSortColumn? = nil,
    sortOrder: SortOrder? = nil,
    search: String? = nil
  ) async throws -> [AnalyticBucket] {
    var query: [URLQueryItem] = []
    if let limit { query.append(URLQueryItem(name: "limit", value: String(limit))) }
    if let offset { query.append(URLQueryItem(name: "offset", value: String(offset))) }
    if let sortColumn { query.append(URLQueryItem(name: "sortColumn", value: sortColumn.rawValue)) }
    if let sortOrder { query.append(URLQueryItem(name: "sortOrder", value: sortOrder.rawValue)) }
    if let search { query.append(URLQueryItem(name: "search", value: search)) }

    return try await api.execute(
      HTTPRequest(
        url: api.configuration.url.appendingPathComponent("iceberg/bucket"),
        method: .get,
        query: query
      )
    )
    .decoded(decoder: .supabase())
  }

  /// Deletes an analytics bucket.
  ///
  /// > Important: A bucket cannot be deleted while it contains namespaces. Drop all namespaces
  /// > first.
  ///
  /// ```swift
  /// try await client.storage.analytics.deleteBucket("events")
  /// ```
  ///
  /// - Warning: Experimental. See ``AnalyticsClient``.
  ///
  /// - Parameter name: The name of the bucket to delete.
  /// - Throws: ``StorageError`` when the API rejects the request.
  public func deleteBucket(_ name: String) async throws {
    try await api.execute(
      HTTPRequest(
        url: api.configuration.url.appendingPathComponent("iceberg/bucket/\(name)"),
        method: .delete
      )
    )
  }

  /// Returns a client scoped to the given analytics bucket, for managing its Iceberg namespaces
  /// and tables.
  ///
  /// ```swift
  /// let bucket = client.storage.analytics.from("events")
  /// try await bucket.createNamespace("default")
  /// ```
  ///
  /// - Warning: Experimental. See ``AnalyticsClient``.
  ///
  /// - Parameter bucketName: The name of the analytics bucket to operate on.
  /// - Returns: An ``AnalyticsBucketClient`` configured for the given bucket.
  public func from(_ bucketName: String) -> AnalyticsBucketClient {
    AnalyticsBucketClient(bucketName: bucketName, api: api)
  }
}

private struct CreateAnalyticBucketBody: Encodable {
  var name: String
}

/// An analytics (Iceberg-backed) Storage bucket.
///
/// - Warning: Experimental. See ``AnalyticsClient``.
@_spi(Experimental)
public struct AnalyticBucket: Decodable, Sendable, Hashable {
  /// The unique identifier of the bucket, equal to ``name``.
  public var id: String

  /// The name of the bucket.
  public var name: String

  /// When the bucket was created.
  public var createdAt: Date

  /// When the bucket was last updated.
  public var updatedAt: Date

  private enum CodingKeys: String, CodingKey {
    case id
    case name
    case createdAt = "created_at"
    case updatedAt = "updated_at"
  }
}

/// A column to sort analytics buckets by, for
/// ``AnalyticsClient/listBuckets(limit:offset:sortColumn:sortOrder:search:)``.
///
/// - Warning: Experimental. See ``AnalyticsClient``.
@_spi(Experimental)
public struct AnalyticsBucketSortColumn: RawRepresentable, Hashable, Sendable {
  /// The raw string value sent to the API.
  public let rawValue: String

  /// Creates an ``AnalyticsBucketSortColumn`` from a raw string value.
  public init(rawValue: String) { self.rawValue = rawValue }

  /// Sort by bucket name.
  public static let name = AnalyticsBucketSortColumn(rawValue: "name")

  /// Sort by creation time.
  public static let createdAt = AnalyticsBucketSortColumn(rawValue: "created_at")

  /// Sort by last-updated time.
  public static let updatedAt = AnalyticsBucketSortColumn(rawValue: "updated_at")
}

extension AnalyticsBucketSortColumn: ExpressibleByStringLiteral {
  public init(stringLiteral value: String) { self.init(rawValue: value) }
}
