//
//  VectorIndexClient.swift
//  Storage
//
//  Created by Guilherme Souza on 06/08/26.
//

import Foundation
import HTTPTypes

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// A client scoped to a single vector index, for reading and writing its vector data.
///
/// Obtain an instance via ``VectorBucketClient/index(_:)``:
///
/// ```swift
/// let index = client.storage.vectors.from("documents").index("embeddings")
///
/// try await index.putVectors([
///   VectorEntry(key: "doc-1", data: VectorData(float32: [0.1, 0.2, 0.3]), metadata: ["title": "Intro"])
/// ])
///
/// let results = try await index.queryVectors(
///   VectorData(float32: [0.1, 0.2, 0.3]),
///   topK: 5,
///   returnMetadata: true
/// )
/// ```
///
/// - Warning: Vector buckets are a public alpha feature of Supabase Storage and this API is
///   experimental — it may change in a breaking way, or be unavailable on your project, until it
///   reaches general availability. Opt in with `@_spi(Experimental) import Supabase`.
///
/// ## Topics
///
/// ### Writing vectors
///
/// - ``putVectors(_:)``
/// - ``deleteVectors(keys:)``
///
/// ### Reading vectors
///
/// - ``getVectors(keys:returnData:returnMetadata:)``
/// - ``listVectors(maxResults:nextToken:returnData:returnMetadata:segment:)``
/// - ``queryVectors(_:topK:filter:returnDistance:returnMetadata:)``
@_spi(Experimental)
public class VectorIndexClient: StorageApi, @unchecked Sendable {
  /// The name of the vector bucket containing ``indexName``.
  public let vectorBucketName: String

  /// The name of the index this client operates on.
  public let indexName: String

  init(vectorBucketName: String, indexName: String, configuration: StorageClientConfiguration) {
    self.vectorBucketName = vectorBucketName
    self.indexName = indexName
    super.init(configuration: configuration)
  }

  /// Inserts or updates vectors in this index, in batches of 1-500 entries.
  ///
  /// Entries are upserted by ``VectorEntry/key``: an existing vector with the same key is
  /// replaced.
  ///
  /// ```swift
  /// try await index.putVectors([
  ///   VectorEntry(
  ///     key: "doc-1",
  ///     data: VectorData(float32: [0.1, 0.2, 0.3]),
  ///     metadata: ["title": "Introduction", "page": 1]
  ///   )
  /// ])
  /// ```
  ///
  /// - Warning: Experimental. See ``StorageVectorsClient``.
  ///
  /// - Parameter vectors: The vectors to insert or update.
  /// - Throws: ``StorageError`` when the API rejects the request.
  public func putVectors(_ vectors: [VectorEntry]) async throws {
    try await execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("vector/PutVectors"),
        method: .post,
        body: JSONEncoder.unconfiguredEncoder.encode(
          PutVectorsBody(
            vectorBucketName: vectorBucketName,
            indexName: indexName,
            vectors: vectors
          )
        )
      )
    )
  }

  /// Retrieves vectors by key, in batches of up to 100 keys.
  ///
  /// ```swift
  /// let vectors = try await index.getVectors(keys: ["doc-1", "doc-2"], returnMetadata: true)
  /// ```
  ///
  /// - Warning: Experimental. See ``StorageVectorsClient``.
  ///
  /// - Parameters:
  ///   - keys: The keys of the vectors to retrieve.
  ///   - returnData: Whether to include vector embedding data in the response. Defaults to `false`.
  ///   - returnMetadata: Whether to include metadata in the response. Defaults to `false`.
  /// - Returns: The matching vectors, in no particular order.
  /// - Throws: ``StorageError`` when the API rejects the request.
  public func getVectors(
    keys: [String],
    returnData: Bool = false,
    returnMetadata: Bool = false
  ) async throws -> [VectorMatch] {
    let response: GetVectorsResponseBody = try await execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("vector/GetVectors"),
        method: .post,
        body: JSONEncoder.unconfiguredEncoder.encode(
          GetVectorsBody(
            vectorBucketName: vectorBucketName,
            indexName: indexName,
            keys: keys,
            returnData: returnData,
            returnMetadata: returnMetadata
          )
        )
      )
    )
    .decoded(decoder: .supabase())
    return response.vectors
  }

  /// Lists vectors in this index with pagination.
  ///
  /// Results are paginated: pass the ``ListVectorsResponse/nextToken`` of a previous response as
  /// `nextToken` to fetch the following page. Use `segment` to scan the index in parallel across
  /// multiple workers.
  ///
  /// ```swift
  /// let page = try await index.listVectors(maxResults: 500, returnMetadata: true)
  /// ```
  ///
  /// - Warning: Experimental. See ``StorageVectorsClient``.
  ///
  /// - Parameters:
  ///   - maxResults: The maximum number of vectors to return in this page (up to 1000).
  ///   - nextToken: The pagination token from a previous response.
  ///   - returnData: Whether to include vector embedding data in the response. Defaults to `false`.
  ///   - returnMetadata: Whether to include metadata in the response. Defaults to `false`.
  ///   - segment: Scans only the given slice of the index, for parallel listing.
  /// - Returns: A page of vectors, plus the token for the next page when more results exist.
  /// - Throws: ``StorageError`` when the API rejects the request.
  public func listVectors(
    maxResults: Int? = nil,
    nextToken: String? = nil,
    returnData: Bool = false,
    returnMetadata: Bool = false,
    segment: VectorListSegment? = nil
  ) async throws -> ListVectorsResponse {
    let response: ListVectorsResponseBody = try await execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("vector/ListVectors"),
        method: .post,
        body: JSONEncoder.unconfiguredEncoder.encode(
          ListVectorsBody(
            vectorBucketName: vectorBucketName,
            indexName: indexName,
            maxResults: maxResults,
            nextToken: nextToken,
            returnData: returnData,
            returnMetadata: returnMetadata,
            segmentCount: segment?.count,
            segmentIndex: segment?.index
          )
        )
      )
    )
    .decoded(decoder: .supabase())
    return ListVectorsResponse(vectors: response.vectors, nextToken: response.nextToken)
  }

  /// Queries for the vectors most similar to `queryVector` using approximate nearest neighbor
  /// search.
  ///
  /// ```swift
  /// let results = try await index.queryVectors(
  ///   VectorData(float32: [0.1, 0.2, 0.3]),
  ///   topK: 5,
  ///   filter: ["category": "technical"],
  ///   returnDistance: true,
  ///   returnMetadata: true
  /// )
  /// ```
  ///
  /// - Warning: Experimental. See ``StorageVectorsClient``.
  ///
  /// - Parameters:
  ///   - queryVector: The vector to find similar vectors for. Must match the index's dimension.
  ///   - topK: The number of nearest neighbors to return (up to 100).
  ///   - filter: A metadata filter expression. Supports field operators (`$eq`, `$ne`, `$gt`,
  ///     `$gte`, `$lt`, `$lte`, `$in`, `$nin`, `$exists`) and logical operators (`$and`, `$or`)
  ///     with arbitrary nesting, e.g. `["category": "technical"]` or
  ///     `["price": ["$gte": 10]]`.
  ///   - returnDistance: Whether to include the similarity distance for each match. Defaults to
  ///     `false`.
  ///   - returnMetadata: Whether to include metadata in the response. Defaults to `false`.
  /// - Returns: The nearest vectors, ordered by ascending distance.
  /// - Throws: ``StorageError`` when the API rejects the request.
  public func queryVectors(
    _ queryVector: VectorData,
    topK: Int,
    filter: [String: AnyJSON]? = nil,
    returnDistance: Bool = false,
    returnMetadata: Bool = false
  ) async throws -> QueryVectorsResponse {
    let response: QueryVectorsResponseBody = try await execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("vector/QueryVectors"),
        method: .post,
        body: JSONEncoder.unconfiguredEncoder.encode(
          QueryVectorsBody(
            vectorBucketName: vectorBucketName,
            indexName: indexName,
            queryVector: queryVector,
            topK: topK,
            filter: filter,
            returnDistance: returnDistance,
            returnMetadata: returnMetadata
          )
        )
      )
    )
    .decoded(decoder: .supabase())
    return QueryVectorsResponse(vectors: response.vectors, distanceMetric: response.distanceMetric)
  }

  /// Deletes vectors by key, in batches of up to 500 keys.
  ///
  /// ```swift
  /// try await index.deleteVectors(keys: ["doc-1", "doc-2"])
  /// ```
  ///
  /// - Warning: Experimental. See ``StorageVectorsClient``.
  ///
  /// - Parameter keys: The keys of the vectors to delete.
  /// - Throws: ``StorageError`` when the API rejects the request.
  public func deleteVectors(keys: [String]) async throws {
    try await execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("vector/DeleteVectors"),
        method: .post,
        body: JSONEncoder.unconfiguredEncoder.encode(
          DeleteVectorsBody(vectorBucketName: vectorBucketName, indexName: indexName, keys: keys)
        )
      )
    )
  }
}

private struct PutVectorsBody: Encodable {
  var vectorBucketName: String
  var indexName: String
  var vectors: [VectorEntry]
}

private struct GetVectorsBody: Encodable {
  var vectorBucketName: String
  var indexName: String
  var keys: [String]
  var returnData: Bool
  var returnMetadata: Bool
}

private struct GetVectorsResponseBody: Decodable {
  var vectors: [VectorMatch]
}

private struct ListVectorsBody: Encodable {
  var vectorBucketName: String
  var indexName: String
  var maxResults: Int?
  var nextToken: String?
  var returnData: Bool
  var returnMetadata: Bool
  var segmentCount: Int?
  var segmentIndex: Int?
}

private struct ListVectorsResponseBody: Decodable {
  var vectors: [VectorMatch]
  var nextToken: String?
}

private struct QueryVectorsBody: Encodable {
  var vectorBucketName: String
  var indexName: String
  var queryVector: VectorData
  var topK: Int
  var filter: [String: AnyJSON]?
  var returnDistance: Bool
  var returnMetadata: Bool
}

private struct QueryVectorsResponseBody: Decodable {
  var vectors: [VectorMatch]
  var distanceMetric: VectorDistanceMetric?
}

private struct DeleteVectorsBody: Encodable {
  var vectorBucketName: String
  var indexName: String
  var keys: [String]
}

/// A vector embedding, currently always 32-bit floating point components.
///
/// - Warning: Experimental. See ``StorageVectorsClient``.
@_spi(Experimental)
public struct VectorData: Codable, Sendable, Hashable {
  /// The vector's components.
  public var float32: [Float]

  /// Creates a ``VectorData`` value.
  ///
  /// - Parameter float32: The vector's components. Must match the index's configured dimension.
  public init(float32: [Float]) {
    self.float32 = float32
  }
}

/// A single vector to insert or update via ``VectorIndexClient/putVectors(_:)``.
///
/// - Warning: Experimental. See ``StorageVectorsClient``.
@_spi(Experimental)
public struct VectorEntry: Codable, Sendable, Hashable {
  /// A unique identifier for the vector within its index.
  public var key: String

  /// The vector's embedding data.
  public var data: VectorData

  /// Arbitrary metadata to store alongside the vector.
  public var metadata: [String: AnyJSON]?

  /// Creates a ``VectorEntry``.
  ///
  /// - Parameters:
  ///   - key: A unique identifier for the vector within its index.
  ///   - data: The vector's embedding data.
  ///   - metadata: Arbitrary metadata to store alongside the vector.
  public init(key: String, data: VectorData, metadata: [String: AnyJSON]? = nil) {
    self.key = key
    self.data = data
    self.metadata = metadata
  }
}

/// A vector returned from ``VectorIndexClient/getVectors(keys:returnData:returnMetadata:)``,
/// ``VectorIndexClient/listVectors(maxResults:nextToken:returnData:returnMetadata:segment:)``, or
/// ``VectorIndexClient/queryVectors(_:topK:filter:returnDistance:returnMetadata:)``.
///
/// - Warning: Experimental. See ``StorageVectorsClient``.
@_spi(Experimental)
public struct VectorMatch: Codable, Sendable, Hashable {
  /// The vector's unique key.
  public var key: String

  /// The vector's embedding data, present when the request set `returnData: true`.
  public var data: VectorData?

  /// The vector's metadata, present when the request set `returnMetadata: true`.
  public var metadata: [String: AnyJSON]?

  /// The similarity distance from the query vector, present when the request set
  /// `returnDistance: true`. Only populated by
  /// ``VectorIndexClient/queryVectors(_:topK:filter:returnDistance:returnMetadata:)``.
  public var distance: Double?
}

/// A parallel scan segment for
/// ``VectorIndexClient/listVectors(maxResults:nextToken:returnData:returnMetadata:segment:)``.
///
/// Splitting a list operation across `count` segments and listing each `index` concurrently lets
/// multiple workers scan a large index in parallel.
///
/// - Warning: Experimental. See ``StorageVectorsClient``.
@_spi(Experimental)
public struct VectorListSegment: Sendable, Hashable {
  /// The total number of parallel segments (1-16).
  public var count: Int

  /// This segment's zero-based index (`0..<count`).
  public var index: Int

  /// Creates a ``VectorListSegment``.
  ///
  /// - Parameters:
  ///   - count: The total number of parallel segments (1-16).
  ///   - index: This segment's zero-based index (`0..<count`).
  public init(count: Int, index: Int) {
    self.count = count
    self.index = index
  }
}

/// A page of vectors, as returned by
/// ``VectorIndexClient/listVectors(maxResults:nextToken:returnData:returnMetadata:segment:)``.
///
/// - Warning: Experimental. See ``StorageVectorsClient``.
@_spi(Experimental)
public struct ListVectorsResponse: Sendable {
  /// The vectors in this page.
  public var vectors: [VectorMatch]

  /// The pagination token to pass to fetch the next page, or `nil` when there are no more results.
  public var nextToken: String?
}

/// The result of a similarity search, as returned by
/// ``VectorIndexClient/queryVectors(_:topK:filter:returnDistance:returnMetadata:)``.
///
/// - Warning: Experimental. See ``StorageVectorsClient``.
@_spi(Experimental)
public struct QueryVectorsResponse: Sendable {
  /// The nearest vectors, ordered by ascending distance.
  public var vectors: [VectorMatch]

  /// The distance metric used for the similarity search.
  public var distanceMetric: VectorDistanceMetric?
}
