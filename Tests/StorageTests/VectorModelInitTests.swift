//
//  VectorModelInitTests.swift
//  Storage
//
//  Created by Guilherme Souza on 09/11/26.
//

import Foundation
import Testing

// Not `@testable`: the memberwise inits must be public so apps can build fixtures and previews.
@_spi(Experimental) import Storage

@Suite
struct VectorModelInitTests {
  @Test
  func vectorBucketModelsHavePublicInits() {
    let created = Date(timeIntervalSince1970: 1_730_000_000)
    let bucket = VectorBucket(vectorBucketName: "documents", creationTime: created)
    let page = VectorBucketPage(vectorBuckets: [bucket], nextToken: "t1")

    #expect(page.vectorBuckets == [bucket])
    #expect(page.nextToken == "t1")
    #expect(bucket.creationTime == created)
  }

  @Test
  func vectorIndexModelsHavePublicInits() {
    let index = VectorIndex(
      indexName: "embeddings",
      vectorBucketName: "documents",
      dataType: .float32,
      dimension: 3,
      distanceMetric: .cosine,
      metadataConfiguration: VectorIndexMetadataConfiguration(nonFilterableMetadataKeys: ["raw"]),
      creationTime: nil
    )
    let summary = VectorIndexSummary(
      indexName: "embeddings", vectorBucketName: "documents", creationTime: nil)
    let page = VectorIndexPage(indexes: [summary], nextToken: nil)

    #expect(index.dimension == 3)
    #expect(page.indexes == [summary])
  }

  @Test
  func vectorDataModelsHavePublicInits() {
    let match = VectorMatch(
      key: "doc-1", data: VectorData(float32: [0.1]), metadata: ["k": "v"], distance: 0.5)
    let page = VectorPage(vectors: [match], nextToken: "t2")
    let response = QueryVectorsResponse(vectors: [match], distanceMetric: .cosine)

    #expect(page.vectors == [match])
    #expect(response.vectors == [match])
    #expect(response.distanceMetric == .cosine)
  }
}
