//
//  VectorListingIntegrationTests.swift
//
//
//  Created by Guilherme Souza on 14/10/26.
//

import Foundation
@_spi(Experimental) import Storage
import Testing

/// The Vectors listings page through `nextToken`, and timestamps decode as dates.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil), .serialized)
struct VectorListingIntegrationTests {
  let vectors = StorageIntegration.admin.vectors

  @Test
  func bucketsAndIndexesPageThroughNextToken() async throws {
    let prefix = "vector-listing-\(UUID().uuidString.lowercased().prefix(8))"
    let names = ["\(prefix)-a", "\(prefix)-b"]
    for name in names { try await vectors.createBucket(name) }
    defer {
      Task { [vectors] in
        for name in names {
          try? await vectors.from(name).deleteIndex("idx1")
          try? await vectors.from(name).deleteIndex("idx2")
          try? await vectors.deleteBucket(name)
        }
      }
    }

    var buckets: [VectorBucket] = []
    for try await bucket in vectors.listBuckets(prefix: prefix, maxResults: 1) {
      buckets.append(bucket)
    }
    #expect(buckets.map(\.vectorBucketName).sorted() == names)
    #expect(buckets.allSatisfy { ($0.creationTime?.timeIntervalSinceNow ?? -.infinity) > -600 })

    let bucket = vectors.from(names[0])
    for index in ["idx1", "idx2"] {
      try await bucket.createIndex(index, dimension: 2, distanceMetric: .cosine)
    }
    var pages = 0
    var indexes: [String] = []
    for try await page in bucket.listIndexes(maxResults: 1).pages {
      pages += 1
      indexes += page.indexes.map(\.indexName)
    }
    #expect(pages == 2)
    #expect(indexes.sorted() == ["idx1", "idx2"])
  }

  @Test
  func vectorsPageThroughNextToken() async throws {
    let name = "vector-listing-\(UUID().uuidString.lowercased().prefix(8))"
    try await vectors.createBucket(name)
    defer {
      Task { [vectors] in
        try? await vectors.from(name).deleteIndex("idx")
        try? await vectors.deleteBucket(name)
      }
    }
    try await vectors.from(name).createIndex("idx", dimension: 2, distanceMetric: .cosine)
    let index = vectors.from(name).index("idx")
    try await index.putVectors(
      (0..<3).map { VectorEntry(key: "k\($0)", data: VectorData(float32: [1, Float($0)])) })

    var keys: [String] = []
    for try await vector in index.listVectors(maxResults: 1) {
      keys.append(vector.key)
    }

    #expect(keys.sorted() == ["k0", "k1", "k2"])
  }

  @Test
  func storageRefusesABatchOutsideItsLimits() async throws {
    let name = "vector-limits-\(UUID().uuidString.lowercased().prefix(8))"
    try await vectors.createBucket(name)
    defer {
      Task { [vectors] in
        try? await vectors.from(name).deleteIndex("idx")
        try? await vectors.deleteBucket(name)
      }
    }
    try await vectors.from(name).createIndex("idx", dimension: 2, distanceMetric: .cosine)
    let index = vectors.from(name).index("idx")
    let entries = { (count: Int) in
      (0..<count).map { VectorEntry(key: "k\($0)", data: VectorData(float32: [1, Float($0)])) }
    }
    let keys = { (count: Int) in (0..<count).map { "k\($0)" } }

    let errors = [
      await StorageIntegration.storageError { try await index.putVectors(entries(0)) },
      await StorageIntegration.storageError { try await index.putVectors(entries(501)) },
      await StorageIntegration.storageError { try await index.deleteVectors(keys: keys(0)) },
      await StorageIntegration.storageError { try await index.deleteVectors(keys: keys(501)) },
      await StorageIntegration.storageError { _ = try await index.vectors(keys: keys(0)) },
      await StorageIntegration.storageError { _ = try await index.vectors(keys: keys(101)) },
    ]

    #expect(errors.map { $0?.kind } == Array(repeating: .server, count: 6))
    #expect(errors.map { $0?.code } == Array(repeating: .invalidRequest, count: 6))
  }
}
