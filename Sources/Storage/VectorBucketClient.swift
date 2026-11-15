//
//  VectorBucketClient.swift
//  Storage
//
//  Created by Guilherme Souza on 06/08/26.
//

public import Foundation
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
/// let index = bucket.from("embeddings")
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
/// - ``index(_:)``
/// - ``listIndexes(options:)``
/// - ``ListIndexesOptions``
/// - ``deleteIndex(_:)``
///
/// ### Accessing vector data
///
/// - ``from(_:)``
@_spi(Experimental)
public struct VectorBucketClient: Sendable {
  /// The name of the vector bucket this client operates on.
  public let vectorBucketName: String

  private let api: StorageAPI

  init(vectorBucketName: String, api: StorageAPI) {
    self.vectorBucketName = vectorBucketName
    self.api = api
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
    try await api.execute(
      HTTPRequest(
        method: .post,
        url: api.configuration.url.appendingPathComponent("vector/CreateIndex")
      ),
      body: JSONEncoder.storage.encode(
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
  }

  /// Retrieves metadata for an existing vector index in this bucket.
  ///
  /// ```swift
  /// let index = try await bucket.index("embeddings")
  /// print(index.dimension)
  /// ```
  ///
  /// - Warning: Experimental. See ``StorageVectorsClient``.
  ///
  /// - Parameter indexName: The name of the index to retrieve.
  /// - Returns: The matching ``VectorIndex``.
  /// - Throws: ``StorageError`` when the API rejects the request.
  public func index(_ indexName: String) async throws -> VectorIndex {
    let response: GetIndexResponseBody = try await api.execute(
      HTTPRequest(
        method: .post,
        url: api.configuration.url.appendingPathComponent("vector/GetIndex")
      ),
      body: JSONEncoder.storage.encode(
        VectorBucketIndexNameBody(vectorBucketName: vectorBucketName, indexName: indexName)
      )
    )
    .decoded(decoder: .vectors)
    return response.index
  }

  /// Lists the vector indexes in this bucket, optionally filtered by name prefix, one page per
  /// request as you iterate.
  ///
  /// ```swift
  /// for try await index in bucket.listIndexes(options: .init(prefix: "embeddings-")) {
  ///   print(index.indexName)
  /// }
  /// ```
  ///
  /// - Warning: Experimental. See ``StorageVectorsClient``.
  ///
  /// - Parameter options: The name prefix filter and page size.
  /// - Returns: The listing. Iterating it, or calling its `page(after:)`, throws ``StorageError``
  ///   when the API rejects a request.
  public func listIndexes(
    options: ListIndexesOptions = ListIndexesOptions()
  ) -> PageSequence<VectorIndexSummary, VectorIndexPage, String> {
    PageSequence(
      fetch: { [api, vectorBucketName] nextToken in
        let response: ListIndexesResponseBody = try await api.execute(
          HTTPRequest(
            method: .post,
            url: api.configuration.url.appendingPathComponent("vector/ListIndexes")
          ),
          body: JSONEncoder.storage.encode(
            ListIndexesBody(
              vectorBucketName: vectorBucketName,
              prefix: options.prefix,
              maxResults: options.pageSize,
              nextToken: nextToken
            )
          )
        )
        .decoded(decoder: .vectors)
        return VectorIndexPage(indexes: response.indexes, nextToken: response.nextToken)
      },
      nextCursor: \.nextToken,
      elements: \.indexes
    )
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
    try await api.execute(
      HTTPRequest(
        method: .post,
        url: api.configuration.url.appendingPathComponent("vector/DeleteIndex")
      ),
      body: JSONEncoder.storage.encode(
        VectorBucketIndexNameBody(vectorBucketName: vectorBucketName, indexName: indexName)
      )
    )
  }

  /// Returns a client scoped to the given index, for reading and writing vector data.
  ///
  /// ```swift
  /// let index = client.storage.vectors.from("documents").from("embeddings")
  /// try await index.putVectors([
  ///   VectorEntry(key: "doc-1", data: VectorData(float32: [0.1, 0.2, 0.3]))
  /// ])
  /// ```
  ///
  /// - Warning: Experimental. See ``StorageVectorsClient``.
  ///
  /// - Parameter indexName: The name of the index.
  /// - Returns: A ``VectorIndexClient`` configured for the given index.
  public func from(_ indexName: String) -> VectorIndexClient {
    VectorIndexClient(
      vectorBucketName: vectorBucketName,
      indexName: indexName,
      api: api
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
  /// Creates a ``VectorDataType`` from a string literal.
  public init(stringLiteral value: String) { self.init(rawValue: value) }
}

extension VectorDataType: Codable {
  /// Encodes the raw value as a single string.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  /// Decodes the raw value from a single string.
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
  /// Creates a ``VectorDistanceMetric`` from a string literal.
  public init(stringLiteral value: String) { self.init(rawValue: value) }
}

extension VectorDistanceMetric: Codable {
  /// Encodes the raw value as a single string.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  /// Decodes the raw value from a single string.
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
public struct VectorIndex: Decodable, Sendable, Hashable {
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

  /// When the index was created, if known.
  public var creationTime: Date?

  /// Creates a ``VectorIndex``.
  ///
  /// - Parameters:
  ///   - indexName: The name of the index.
  ///   - vectorBucketName: The name of the vector bucket this index belongs to.
  ///   - dataType: The data type of the vector components.
  ///   - dimension: The dimensionality of vectors stored in this index.
  ///   - distanceMetric: The similarity metric used when querying this index.
  ///   - metadataConfiguration: Which metadata keys are excluded from filtering, if any.
  ///   - creationTime: When the index was created, if known.
  public init(
    indexName: String,
    vectorBucketName: String,
    dataType: VectorDataType,
    dimension: Int,
    distanceMetric: VectorDistanceMetric,
    metadataConfiguration: VectorIndexMetadataConfiguration? = nil,
    creationTime: Date? = nil
  ) {
    self.indexName = indexName
    self.vectorBucketName = vectorBucketName
    self.dataType = dataType
    self.dimension = dimension
    self.distanceMetric = distanceMetric
    self.metadataConfiguration = metadataConfiguration
    self.creationTime = creationTime
  }
}

/// A summary of a vector index, as returned by
/// ``VectorBucketClient/listIndexes(options:)``.
///
/// - Warning: Experimental. See ``StorageVectorsClient``.
@_spi(Experimental)
public struct VectorIndexSummary: Decodable, Sendable, Hashable {
  /// The name of the index.
  public var indexName: String

  /// The name of the vector bucket this index belongs to.
  public var vectorBucketName: String

  /// When the index was created, if known.
  public var creationTime: Date?

  /// Creates a ``VectorIndexSummary``.
  ///
  /// - Parameters:
  ///   - indexName: The name of the index.
  ///   - vectorBucketName: The name of the vector bucket this index belongs to.
  ///   - creationTime: When the index was created, if known.
  public init(indexName: String, vectorBucketName: String, creationTime: Date? = nil) {
    self.indexName = indexName
    self.vectorBucketName = vectorBucketName
    self.creationTime = creationTime
  }
}

/// A page of vector indexes, as returned by
/// ``VectorBucketClient/listIndexes(options:)``.
///
/// - Warning: Experimental. See ``StorageVectorsClient``.
@_spi(Experimental)
public struct VectorIndexPage: Sendable {
  /// The indexes in this page.
  public var indexes: [VectorIndexSummary]

  /// The pagination token to pass to fetch the next page, or `nil` when there are no more results.
  public var nextToken: String?

  /// Creates a ``VectorIndexPage``.
  ///
  /// - Parameters:
  ///   - indexes: The indexes in this page.
  ///   - nextToken: The pagination token for the next page, or `nil` for the last page.
  public init(indexes: [VectorIndexSummary], nextToken: String? = nil) {
    self.indexes = indexes
    self.nextToken = nextToken
  }
}

/// Options for ``VectorBucketClient/listIndexes(options:)``.
///
/// - Warning: Experimental. See ``StorageVectorsClient``.
@_spi(Experimental)
public struct ListIndexesOptions: Sendable, Hashable {
  /// Returns only indexes whose name starts with this prefix. `nil` returns all indexes.
  public var prefix: String?

  /// The maximum number of indexes per page (up to 500). `nil` uses the server default.
  public var pageSize: Int?

  /// Creates a ``ListIndexesOptions`` value.
  ///
  /// - Parameters:
  ///   - prefix: Returns only indexes whose name starts with this prefix.
  ///   - pageSize: The maximum number of indexes per page (up to 500).
  public init(prefix: String? = nil, pageSize: Int? = nil) {
    self.prefix = prefix
    self.pageSize = pageSize
  }
}
