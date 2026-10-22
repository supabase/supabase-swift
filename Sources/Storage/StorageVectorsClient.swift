//
//  StorageVectorsClient.swift
//  Storage
//
//  Created by Guilherme Souza on 27/07/26.
//

public import Foundation
import HTTPTypes

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// A client for managing Supabase Storage's alpha "vector buckets" feature (`storage.vectors`).
///
/// Obtain an instance via ``StorageClient/vectors``:
///
/// ```swift
/// try await client.storage.vectors.createBucket("documents")
/// for try await bucket in client.storage.vectors.listBuckets() {
///   print(bucket.vectorBucketName)
/// }
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
/// - ``bucket(_:)``
/// - ``listBuckets(prefix:maxResults:)``
/// - ``PagedListing``
/// - ``deleteBucket(_:)``
///
/// ### Managing indexes and vector data
///
/// - ``from(_:)``
@_spi(Experimental)
public struct StorageVectorsClient: Sendable {
  private let api: StorageAPI

  init(api: StorageAPI) {
    self.api = api
  }

  /// Returns a client scoped to the given vector bucket, for managing its indexes and vector data.
  ///
  /// ```swift
  /// let bucket = client.storage.vectors.from("documents")
  /// try await bucket.createIndex("embeddings", dimension: 1536, distanceMetric: .cosine)
  /// ```
  ///
  /// - Warning: Experimental. See ``StorageVectorsClient``.
  ///
  /// - Parameter vectorBucketName: The name of the vector bucket to operate on.
  /// - Returns: A ``VectorBucketClient`` configured for the given bucket.
  public func from(_ vectorBucketName: String) -> VectorBucketClient {
    VectorBucketClient(vectorBucketName: vectorBucketName, api: api)
  }

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
    try await api.execute(
      HTTPRequest(
        method: .post,
        url: api.configuration.url.appendingPathComponent("vector/CreateVectorBucket")
      ), body: JSONEncoder.storage.encode(VectorBucketNameBody(vectorBucketName: name))
    )
  }

  /// Retrieves the details of an existing vector bucket.
  ///
  /// ```swift
  /// let bucket = try await client.storage.vectors.bucket("documents")
  /// print(bucket.vectorBucketName)
  /// ```
  ///
  /// - Warning: Experimental. See ``StorageVectorsClient``.
  ///
  /// - Parameter name: The name of the vector bucket to fetch.
  /// - Returns: The matching ``VectorBucket``.
  /// - Throws: ``StorageError`` when the API rejects the request.
  public func bucket(_ name: String) async throws -> VectorBucket {
    let response: GetVectorBucketResponseBody = try await api.execute(
      HTTPRequest(
        method: .post,
        url: api.configuration.url.appendingPathComponent("vector/GetVectorBucket")
      ), body: JSONEncoder.storage.encode(VectorBucketNameBody(vectorBucketName: name))
    )
    .decoded(decoder: .vectors)
    return response.vectorBucket
  }

  /// Lists the vector buckets in the project, optionally filtered by name prefix, one page per
  /// request as you iterate.
  ///
  /// ```swift
  /// for try await bucket in client.storage.vectors.listBuckets(prefix: "docs") {
  ///   print(bucket.vectorBucketName)
  /// }
  ///
  /// // One page at a time
  /// let page = try await client.storage.vectors.listBuckets().page(after: savedToken)
  /// ```
  ///
  /// - Warning: Experimental. See ``StorageVectorsClient``.
  ///
  /// - Parameters:
  ///   - prefix: Returns only buckets whose name starts with this prefix. Pass `nil` for all buckets.
  ///   - maxResults: The maximum number of buckets per page (up to 500).
  /// - Returns: The listing. Iterating it throws ``StorageError`` when the API rejects a request.
  public func listBuckets(
    prefix: String? = nil,
    maxResults: Int? = nil
  ) -> PagedListing<ListVectorBucketsResponse, VectorBucket> {
    PagedListing(
      fetch: { [api] nextToken in
        let response: ListVectorBucketsResponseBody = try await api.execute(
          HTTPRequest(
            method: .post,
            url: api.configuration.url.appendingPathComponent("vector/ListVectorBuckets")
          ),
          body: JSONEncoder.storage.encode(
            VectorBucketListBody(maxResults: maxResults, nextToken: nextToken, prefix: prefix)
          )
        )
        .decoded(decoder: .vectors)
        return ListVectorBucketsResponse(
          vectorBuckets: response.vectorBuckets,
          nextToken: response.nextToken
        )
      },
      nextToken: \.nextToken,
      elements: \.vectorBuckets
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
    try await api.execute(
      HTTPRequest(
        method: .post,
        url: api.configuration.url.appendingPathComponent("vector/DeleteVectorBucket")
      ), body: JSONEncoder.storage.encode(VectorBucketNameBody(vectorBucketName: name))
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
public struct VectorBucket: Decodable, Sendable, Hashable {
  /// The name of the vector bucket.
  public var vectorBucketName: String

  /// When the bucket was created, if known.
  public var creationTime: Date?
}

/// A page of vector buckets, as returned by
/// ``StorageVectorsClient/listBuckets(prefix:maxResults:)``.
///
/// - Warning: Experimental. See ``StorageVectorsClient``.
@_spi(Experimental)
public struct ListVectorBucketsResponse: Sendable {
  /// The buckets in this page.
  public var vectorBuckets: [VectorBucket]

  /// The pagination token to pass to fetch the next page, or `nil` when there are no more results.
  public var nextToken: String?
}
