//
//  VectorBucketClient.swift
//  Storage
//
//  Created by Guilherme Souza on 06/08/26.
//

import Foundation
import HTTPTypes

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// A client scoped to a single vector bucket, for managing its indexes and vector data.
///
/// Obtain an instance via ``StorageVectorsClient/from(_:)``:
///
/// ```swift
/// let bucket = client.storage.vectors.from("documents")
/// try await bucket.createIndex("embeddings", dimension: 1536, distanceMetric: .cosine)
/// let index = bucket.index("embeddings")
/// ```
///
/// - Warning: Vector buckets are a public alpha feature of Supabase Storage and this API is
///   experimental — it may change in a breaking way, or be unavailable on your project, until it
///   reaches general availability. Opt in with `@_spi(Experimental) import Supabase`.
///
/// ## Topics
///
/// ### Managing indexes
///
/// - ``createIndex(_:dimension:distanceMetric:dataType:metadataConfiguration:)``
/// - ``getIndex(_:)``
/// - ``listIndexes(prefix:maxResults:nextToken:)``
/// - ``deleteIndex(_:)``
///
/// ### Accessing vector data
///
/// - ``index(_:)``
@_spi(Experimental)
public class VectorBucketClient: StorageApi, @unchecked Sendable {
  /// The name of the vector bucket this client operates on.
  public let vectorBucketName: String

  init(vectorBucketName: String, configuration: StorageClientConfiguration) {
    self.vectorBucketName = vectorBucketName
    super.init(configuration: configuration)
  }

  /// Creates a new vector index within this bucket.
  ///
  /// ```swift
  /// try await bucket.createIndex(
  ///   "embeddings",
  ///   dimension: 1536,
  ///   distanceMetric: .cosine,
  ///   metadataConfiguration: VectorIndexMetadataConfiguration(
  ///     nonFilterableMetadataKeys: ["raw_text"]
  ///   )
  /// )
  /// ```
  ///
  /// - Warning: Experimental. See ``StorageVectorsClient``.
  ///
  /// - Parameters:
  ///   - indexName: A unique name for the index within this bucket. 3-63 characters: lowercase
  ///     letters, numbers, hyphens, and dots, starting and ending with a letter or number.
  ///   - dimension: The dimensionality of vectors stored in this index (e.g. `1536`).
  ///   - distanceMetric: The similarity metric used when querying this index.
  ///   - dataType: The data type of vector components. Defaults to ``VectorDataType/float32``,
  ///     currently the only supported value.
  ///   - metadataConfiguration: Configuration for which metadata keys are excluded from filtering.
  /// - Throws: ``StorageError`` when the API rejects the request.
  public func createIndex(
    _ indexName: String,
    dimension: Int,
    distanceMetric: VectorDistanceMetric,
    dataType: VectorDataType = .float32,
    metadataConfiguration: VectorIndexMetadataConfiguration? = nil
  ) async throws {
    try await execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("vector/CreateIndex"),
        method: .post,
        body: JSONEncoder.unconfiguredEncoder.encode(
          CreateIndexBody(
            vectorBucketName: vectorBucketName,
            indexName: indexName,
            dataType: dataType,
            dimension: dimension,
            distanceMetric: distanceMetric,
            metadataConfiguration: metadataConfiguration
          )
        )
      )
    )
  }

  /// Retrieves metadata for an existing vector index in this bucket.
  ///
  /// ```swift
  /// let index = try await bucket.getIndex("embeddings")
  /// print(index.dimension)
  /// ```
  ///
  /// - Warning: Experimental. See ``StorageVectorsClient``.
  ///
  /// - Parameter indexName: The name of the index to retrieve.
  /// - Returns: The matching ``VectorIndex``.
  /// - Throws: ``StorageError`` when the API rejects the request.
  public func getIndex(_ indexName: String) async throws -> VectorIndex {
    let response: GetIndexResponseBody = try await execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("vector/GetIndex"),
        method: .post,
        body: JSONEncoder.unconfiguredEncoder.encode(
          VectorBucketIndexNameBody(vectorBucketName: vectorBucketName, indexName: indexName)
        )
      )
    )
    .decoded(decoder: .supabase())
    return response.index
  }

  /// Lists the vector indexes in this bucket, optionally filtered by name prefix.
  ///
  /// Results are paginated: pass the ``ListVectorIndexesResponse/nextToken`` of a previous
  /// response as `nextToken` to fetch the following page.
  ///
  /// ```swift
  /// let page = try await bucket.listIndexes(prefix: "embeddings-")
  /// for index in page.indexes {
  ///   print(index.indexName)
  /// }
  /// ```
  ///
  /// - Warning: Experimental. See ``StorageVectorsClient``.
  ///
  /// - Parameters:
  ///   - prefix: Returns only indexes whose name starts with this prefix. Pass `nil` for all
  ///     indexes.
  ///   - maxResults: The maximum number of indexes to return in this page.
  ///   - nextToken: The pagination token from a previous response.
  /// - Returns: A page of indexes, plus the token for the next page when more results exist.
  /// - Throws: ``StorageError`` when the API rejects the request.
  public func listIndexes(
    prefix: String? = nil,
    maxResults: Int? = nil,
    nextToken: String? = nil
  ) async throws -> ListVectorIndexesResponse {
    let response: ListIndexesResponseBody = try await execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("vector/ListIndexes"),
        method: .post,
        body: JSONEncoder.unconfiguredEncoder.encode(
          ListIndexesBody(
            vectorBucketName: vectorBucketName,
            prefix: prefix,
            maxResults: maxResults,
            nextToken: nextToken
          )
        )
      )
    )
    .decoded(decoder: .supabase())
    return ListVectorIndexesResponse(indexes: response.indexes, nextToken: response.nextToken)
  }

  /// Deletes a vector index and all of its vector data.
  ///
  /// ```swift
  /// try await bucket.deleteIndex("embeddings")
  /// ```
  ///
  /// - Warning: Experimental. See ``StorageVectorsClient``.
  ///
  /// - Parameter indexName: The name of the index to delete.
  /// - Throws: ``StorageError`` when the API rejects the request.
  public func deleteIndex(_ indexName: String) async throws {
    try await execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("vector/DeleteIndex"),
        method: .post,
        body: JSONEncoder.unconfiguredEncoder.encode(
          VectorBucketIndexNameBody(vectorBucketName: vectorBucketName, indexName: indexName)
        )
      )
    )
  }

  /// Returns a client scoped to the given index, for reading and writing vector data.
  ///
  /// ```swift
  /// let index = client.storage.vectors.from("documents").index("embeddings")
  /// try await index.putVectors([
  ///   VectorEntry(key: "doc-1", data: VectorData(float32: [0.1, 0.2, 0.3]))
  /// ])
  /// ```
  ///
  /// - Warning: Experimental. See ``StorageVectorsClient``.
  ///
  /// - Parameter indexName: The name of the index.
  /// - Returns: A ``VectorIndexClient`` configured for the given index.
  public func index(_ indexName: String) -> VectorIndexClient {
    VectorIndexClient(
      vectorBucketName: vectorBucketName,
      indexName: indexName,
      configuration: configuration
    )
  }
}

private struct VectorBucketIndexNameBody: Encodable {
  var vectorBucketName: String
  var indexName: String
}

private struct CreateIndexBody: Encodable {
  var vectorBucketName: String
  var indexName: String
  var dataType: VectorDataType
  var dimension: Int
  var distanceMetric: VectorDistanceMetric
  var metadataConfiguration: VectorIndexMetadataConfiguration?
}

private struct ListIndexesBody: Encodable {
  var vectorBucketName: String
  var prefix: String?
  var maxResults: Int?
  var nextToken: String?
}

private struct GetIndexResponseBody: Decodable {
  var index: VectorIndex
}

private struct ListIndexesResponseBody: Decodable {
  var indexes: [VectorIndexSummary]
  var nextToken: String?
}

/// The data type of the components stored in a vector index.
///
/// ```swift
/// try await bucket.createIndex("embeddings", dimension: 1536, distanceMetric: .cosine, dataType: .float32)
/// ```
///
/// ## Topics
///
/// ### Predefined data types
///
/// - ``float32``
@_spi(Experimental)
public struct VectorDataType: RawRepresentable, Hashable, Sendable {
  /// The raw string value sent to the API.
  public let rawValue: String

  /// Creates a ``VectorDataType`` from a raw string value.
  ///
  /// - Parameter rawValue: The data type string understood by the Storage vectors API.
  public init(rawValue: String) { self.rawValue = rawValue }

  /// 32-bit floating point vector components. Currently the only supported data type.
  public static let float32 = VectorDataType(rawValue: "float32")
}

extension VectorDataType: ExpressibleByStringLiteral {
  public init(stringLiteral value: String) { self.init(rawValue: value) }
}

extension VectorDataType: Codable {
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    self.init(rawValue: try container.decode(String.self))
  }
}

/// The similarity metric used to rank results when querying a vector index.
///
/// ```swift
/// try await bucket.createIndex("embeddings", dimension: 1536, distanceMetric: .cosine)
/// ```
///
/// ## Topics
///
/// ### Predefined metrics
///
/// - ``cosine``
/// - ``euclidean``
/// - ``dotProduct``
@_spi(Experimental)
public struct VectorDistanceMetric: RawRepresentable, Hashable, Sendable {
  /// The raw string value sent to the API.
  public let rawValue: String

  /// Creates a ``VectorDistanceMetric`` from a raw string value.
  ///
  /// - Parameter rawValue: The distance metric string understood by the Storage vectors API.
  public init(rawValue: String) { self.rawValue = rawValue }

  /// Cosine similarity.
  public static let cosine = VectorDistanceMetric(rawValue: "cosine")

  /// Euclidean (L2) distance.
  public static let euclidean = VectorDistanceMetric(rawValue: "euclidean")

  /// Dot product similarity.
  ///
  /// - Note: Support depends on the underlying vector store backend.
  public static let dotProduct = VectorDistanceMetric(rawValue: "dotproduct")
}

extension VectorDistanceMetric: ExpressibleByStringLiteral {
  public init(stringLiteral value: String) { self.init(rawValue: value) }
}

extension VectorDistanceMetric: Codable {
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    self.init(rawValue: try container.decode(String.self))
  }
}

/// Configuration for which metadata keys are excluded from filtering on a vector index.
///
/// - Warning: Experimental. See ``StorageVectorsClient``.
@_spi(Experimental)
public struct VectorIndexMetadataConfiguration: Codable, Sendable, Hashable {
  /// Metadata keys that can be stored but not used in ``VectorIndexClient`` query filters.
  public var nonFilterableMetadataKeys: [String]

  /// Creates a ``VectorIndexMetadataConfiguration``.
  ///
  /// - Parameter nonFilterableMetadataKeys: Metadata keys to exclude from filtering.
  public init(nonFilterableMetadataKeys: [String]) {
    self.nonFilterableMetadataKeys = nonFilterableMetadataKeys
  }
}

/// A vector index, as returned by ``VectorBucketClient``.
///
/// - Warning: Experimental. See ``StorageVectorsClient``.
@_spi(Experimental)
public struct VectorIndex: Codable, Sendable, Hashable {
  /// The name of the index.
  public var indexName: String

  /// The name of the vector bucket this index belongs to.
  public var vectorBucketName: String

  /// The data type of the vector components stored in this index.
  public var dataType: VectorDataType

  /// The dimensionality of vectors stored in this index.
  public var dimension: Int

  /// The similarity metric used when querying this index.
  public var distanceMetric: VectorDistanceMetric

  /// Configuration for which metadata keys are excluded from filtering, if any.
  public var metadataConfiguration: VectorIndexMetadataConfiguration?

  /// Unix timestamp (seconds) of when the index was created, if known.
  public var creationTime: Int?
}

/// A summary of a vector index, as returned by
/// ``VectorBucketClient/listIndexes(prefix:maxResults:nextToken:)``.
///
/// - Warning: Experimental. See ``StorageVectorsClient``.
@_spi(Experimental)
public struct VectorIndexSummary: Codable, Sendable, Hashable {
  /// The name of the index.
  public var indexName: String

  /// The name of the vector bucket this index belongs to.
  public var vectorBucketName: String

  /// Unix timestamp (seconds) of when the index was created, if known.
  public var creationTime: Int?
}

/// A page of vector indexes, as returned by
/// ``VectorBucketClient/listIndexes(prefix:maxResults:nextToken:)``.
///
/// - Warning: Experimental. See ``StorageVectorsClient``.
@_spi(Experimental)
public struct ListVectorIndexesResponse: Sendable {
  /// The indexes in this page.
  public var indexes: [VectorIndexSummary]

  /// The pagination token to pass to fetch the next page, or `nil` when there are no more results.
  public var nextToken: String?
}
