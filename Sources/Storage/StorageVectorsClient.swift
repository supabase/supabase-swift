//
//  StorageVectorsClient.swift
//  Storage
//
//  Created by Guilherme Souza on 27/07/26.
//

import Foundation
import HTTPTypes

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// A client for managing Supabase Storage's alpha "vector buckets" feature (`storage.vectors`).
///
/// Obtain an instance via ``SupabaseStorageClient/vectors``:
///
/// ```swift
/// try await client.storage.vectors.createBucket("documents")
/// let buckets = try await client.storage.vectors.listBuckets().vectorBuckets
/// ```
///
/// - Warning: Vector buckets are a public alpha feature of Supabase Storage and this API is
///   experimental — it may change in a breaking way, or be unavailable on your project, until it
///   reaches general availability. Opt in with `@_spi(Experimental) import Supabase`.
///
/// ## Topics
///
/// ### Managing vector buckets
///
/// - ``createBucket(_:)``
/// - ``getBucket(_:)``
/// - ``listBuckets(prefix:maxResults:nextToken:)``
/// - ``deleteBucket(_:)``
@_spi(Experimental)
public class StorageVectorsClient: StorageApi, @unchecked Sendable {
  /// Creates a new vector bucket.
  ///
  /// ```swift
  /// try await client.storage.vectors.createBucket("documents")
  /// ```
  ///
  /// - Warning: Experimental. See ``StorageVectorsClient``.
  ///
  /// - Parameter name: The name of the vector bucket to create.
  /// - Throws: ``StorageError`` when the API rejects the request.
  public func createBucket(_ name: String) async throws {
    try await execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("vector/CreateVectorBucket"),
        method: .post,
        body: JSONEncoder.unconfiguredEncoder.encode(VectorBucketNameBody(vectorBucketName: name))
      )
    )
  }

  /// Retrieves the details of an existing vector bucket.
  ///
  /// ```swift
  /// let bucket = try await client.storage.vectors.getBucket("documents")
  /// print(bucket.vectorBucketName)
  /// ```
  ///
  /// - Warning: Experimental. See ``StorageVectorsClient``.
  ///
  /// - Parameter name: The name of the vector bucket to fetch.
  /// - Returns: The matching ``VectorBucket``.
  /// - Throws: ``StorageError`` when the API rejects the request.
  public func getBucket(_ name: String) async throws -> VectorBucket {
    let response: GetVectorBucketResponseBody = try await execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("vector/GetVectorBucket"),
        method: .post,
        body: JSONEncoder.unconfiguredEncoder.encode(VectorBucketNameBody(vectorBucketName: name))
      )
    )
    .decoded(decoder: .supabase())
    return response.vectorBucket
  }

  /// Lists the vector buckets in the project, optionally filtered by name prefix.
  ///
  /// Results are paginated: pass the ``ListVectorBucketsResponse/nextToken`` of a previous response
  /// as `nextToken` to fetch the following page.
  ///
  /// ```swift
  /// let page = try await client.storage.vectors.listBuckets(prefix: "docs")
  /// for bucket in page.vectorBuckets {
  ///   print(bucket.vectorBucketName)
  /// }
  /// ```
  ///
  /// - Warning: Experimental. See ``StorageVectorsClient``.
  ///
  /// - Parameters:
  ///   - prefix: Returns only buckets whose name starts with this prefix. Pass `nil` for all buckets.
  ///   - maxResults: The maximum number of buckets to return in this page.
  ///   - nextToken: The pagination token from a previous response.
  /// - Returns: A page of buckets, plus the token for the next page when more results exist.
  /// - Throws: ``StorageError`` when the API rejects the request.
  public func listBuckets(
    prefix: String? = nil,
    maxResults: Int? = nil,
    nextToken: String? = nil
  ) async throws -> ListVectorBucketsResponse {
    let response: ListVectorBucketsResponseBody = try await execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("vector/ListVectorBuckets"),
        method: .post,
        body: JSONEncoder.unconfiguredEncoder.encode(
          VectorBucketListBody(maxResults: maxResults, nextToken: nextToken, prefix: prefix)
        )
      )
    )
    .decoded(decoder: .supabase())
    return ListVectorBucketsResponse(
      vectorBuckets: response.vectorBuckets,
      nextToken: response.nextToken
    )
  }

  /// Deletes a vector bucket.
  ///
  /// ```swift
  /// try await client.storage.vectors.deleteBucket("documents")
  /// ```
  ///
  /// - Warning: Experimental. See ``StorageVectorsClient``.
  ///
  /// - Parameter name: The name of the vector bucket to delete.
  /// - Throws: ``StorageError`` when the API rejects the request.
  public func deleteBucket(_ name: String) async throws {
    try await execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("vector/DeleteVectorBucket"),
        method: .post,
        body: JSONEncoder.unconfiguredEncoder.encode(VectorBucketNameBody(vectorBucketName: name))
      )
    )
  }
}

private struct VectorBucketNameBody: Encodable {
  var vectorBucketName: String
}

private struct VectorBucketListBody: Encodable {
  var maxResults: Int?
  var nextToken: String?
  var prefix: String?
}

private struct GetVectorBucketResponseBody: Decodable {
  var vectorBucket: VectorBucket
}

private struct ListVectorBucketsResponseBody: Decodable {
  var vectorBuckets: [VectorBucket]
  var nextToken: String?
}

/// A vector bucket, as returned by ``StorageVectorsClient``.
///
/// - Warning: Experimental. See ``StorageVectorsClient``.
@_spi(Experimental)
public struct VectorBucket: Codable, Sendable, Hashable {
  /// The name of the vector bucket.
  public var vectorBucketName: String

  /// Unix timestamp (seconds) of when the bucket was created, if known.
  public var creationTime: Int?
}

/// A page of vector buckets, as returned by
/// ``StorageVectorsClient/listBuckets(prefix:maxResults:nextToken:)``.
///
/// - Warning: Experimental. See ``StorageVectorsClient``.
@_spi(Experimental)
public struct ListVectorBucketsResponse: Sendable {
  /// The buckets in this page.
  public var vectorBuckets: [VectorBucket]

  /// The pagination token to pass to fetch the next page, or `nil` when there are no more results.
  public var nextToken: String?
}
