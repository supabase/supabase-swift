//
//  VectorIndexClientIntegrationTests.swift
//
//
//  Created by Guilherme Souza on 06/08/26.
//

import Foundation
@_spi(Experimental) import Storage
import Testing

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite(.enabled(if: ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil))
final class VectorIndexClientIntegrationTests {
  let vectors = SupabaseStorageClient(
    configuration: StorageClientConfiguration(
      url: URL(string: "\(DotEnv.SUPABASE_URL)/storage/v1")!,
      headers: [
        "Authorization": "Bearer \(DotEnv.SUPABASE_SECRET_KEY)"
      ]
    )
  ).vectors

  var bucketName = ""

  init() async throws {
    bucketName = "test-vector-bucket-\(UUID().uuidString)"
    try await vectors.createBucket(bucketName)
  }

  // Async cleanup can outlive the test if the process exits immediately after — acceptable for
  // local dev/CI cleanup, not correctness-critical.
  deinit {
    let vectors = vectors
    let bucketName = bucketName
    Task {
      let bucket = vectors.from(bucketName)
      if let indexes = try? await bucket.listIndexes() {
        for index in indexes.indexes {
          try? await bucket.deleteIndex(index.indexName)
        }
      }
      try? await vectors.deleteBucket(bucketName)
    }
  }

  @Test
  func index_CRUD() async throws {
    let bucket = vectors.from(bucketName)
    let indexName = "test-index"

    var page = try await bucket.listIndexes()
    #expect(!page.indexes.contains { $0.indexName == indexName })

    try await bucket.createIndex(
      indexName,
      dimension: 3,
      distanceMetric: .cosine,
      metadataConfiguration: VectorIndexMetadataConfiguration(
        nonFilterableMetadataKeys: ["raw_text"]
      )
    )

    let index = try await bucket.getIndex(indexName)
    #expect(index.indexName == indexName)
    #expect(index.vectorBucketName == bucketName)
    #expect(index.dataType == .float32)
    #expect(index.dimension == 3)
    #expect(index.distanceMetric == .cosine)

    page = try await bucket.listIndexes()
    #expect(page.indexes.contains { $0.indexName == indexName })

    try await bucket.deleteIndex(indexName)

    page = try await bucket.listIndexes()
    #expect(!page.indexes.contains { $0.indexName == indexName })
  }

  @Test
  func putGetListDeleteVectors() async throws {
    let indexName = "test-index"
    let bucket = vectors.from(bucketName)
    try await bucket.createIndex(indexName, dimension: 3, distanceMetric: .cosine)
    let index = bucket.index(indexName)

    try await index.putVectors([
      VectorEntry(
        key: "a", data: VectorData(float32: [0.1, 0.2, 0.3]), metadata: ["type": "doc"]),
      VectorEntry(key: "b", data: VectorData(float32: [0.4, 0.5, 0.6])),
    ])

    let fetched = try await index.getVectors(
      keys: ["a", "b"], returnData: true, returnMetadata: true)
    #expect(fetched.count == 2)
    let a = try #require(fetched.first { $0.key == "a" })
    // The pgvector backend stores embeddings as `halfvec` (half precision), so components
    // round-trip with reduced precision rather than exactly.
    let aData = try #require(a.data?.float32)
    for (actual, expected) in zip(aData, [0.1, 0.2, 0.3] as [Float]) {
      #expect(abs(actual - expected) < 0.001)
    }
    #expect(a.metadata?["type"]?.stringValue == "doc")

    let listed = try await index.listVectors(returnData: true)
    #expect(listed.vectors.map(\.key).sorted() == ["a", "b"])

    try await index.deleteVectors(keys: ["a"])

    let afterDelete = try await index.listVectors()
    #expect(afterDelete.vectors.map(\.key) == ["b"])
  }

  @Test
  func queryVectors() async throws {
    let indexName = "test-index"
    let bucket = vectors.from(bucketName)
    try await bucket.createIndex(indexName, dimension: 2, distanceMetric: .cosine)
    let index = bucket.index(indexName)

    try await index.putVectors([
      VectorEntry(key: "close", data: VectorData(float32: [1.0, 0.0])),
      VectorEntry(key: "far", data: VectorData(float32: [0.0, 1.0])),
    ])

    let response = try await index.queryVectors(
      VectorData(float32: [0.9, 0.1]),
      topK: 2,
      returnDistance: true
    )
    #expect(response.vectors.map(\.key) == ["close", "far"])
    #expect(response.distanceMetric == .cosine)
  }
}
