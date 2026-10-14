//
//  StorageAnalyticsClient.swift
//  Storage
//
//  Created by Guilherme Souza on 14/10/26.
//

public import Foundation

/// A client for Supabase Storage's analytics buckets, which hold Apache Iceberg tables
/// (`storage.analytics`).
///
/// Obtain an instance via ``StorageClient/analytics``:
///
/// ```swift
/// try await client.storage.analytics.createBucket("events")
/// let buckets = try await client.storage.analytics.listBuckets()
/// ```
///
/// Every method needs the `secret` key. The tables themselves are reached through Storage's
/// Iceberg REST catalog with an Iceberg client; this client does not wrap the catalog.
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
/// - ``listBuckets(options:)``
/// - ``deleteBucket(_:)``
/// - ``AnalyticsBucket``
@_spi(Experimental)
public struct StorageAnalyticsClient: Sendable {
  let api: StorageAPI

  /// Creates an analytics bucket.
  ///
  /// - Warning: Experimental. See ``StorageAnalyticsClient``.
  ///
  /// - Parameter name: The name of the bucket, which is also its ID.
  /// - Returns: The created bucket.
  /// - Throws: ``StorageError`` when the API rejects the request, e.g. when the project already
  ///   has the most analytics buckets it may.
  @discardableResult
  public func createBucket(_ name: String) async throws -> AnalyticsBucket {
    try await api.execute(api.requests.createAnalyticsBucket(name)).decoded()
  }

  /// Lists the analytics buckets in the project.
  ///
  /// - Warning: Experimental. See ``StorageAnalyticsClient``.
  ///
  /// - Parameter options: Paging, sort and a name filter. Defaults to every bucket.
  /// - Returns: The buckets.
  /// - Throws: ``StorageError`` when the API rejects the request.
  public func listBuckets(options: BucketListOptions = BucketListOptions()) async throws
    -> [AnalyticsBucket]
  {
    try await api.execute(api.requests.analyticsBuckets(options)).decoded()
  }

  /// Deletes an analytics bucket.
  ///
  /// - Warning: Experimental. See ``StorageAnalyticsClient``.
  ///
  /// - Parameter name: The name of the bucket to delete.
  /// - Throws: ``StorageError`` when the API rejects the request.
  public func deleteBucket(_ name: String) async throws {
    try await api.execute(api.requests.deleteAnalyticsBucket(name))
  }
}

/// An analytics bucket, as returned by ``StorageAnalyticsClient``.
///
/// - Warning: Experimental. See ``StorageAnalyticsClient``.
@_spi(Experimental)
public struct AnalyticsBucket: Identifiable, Hashable, Decodable, Sendable {
  /// The bucket ID, the same as its ``name``.
  public var id: String

  /// The bucket name.
  public var name: String

  /// When the bucket was created.
  public var createdAt: Date

  /// When the bucket was last updated.
  public var updatedAt: Date

  /// Creates an ``AnalyticsBucket``.
  public init(id: String, name: String, createdAt: Date, updatedAt: Date) {
    self.id = id
    self.name = name
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  enum CodingKeys: String, CodingKey {
    case id
    case name
    case createdAt = "created_at"
    case updatedAt = "updated_at"
  }
}
