//
//  VectorBucketClientTests.swift
//  Storage
//
//  Created by Guilherme Souza on 06/08/26.
//
import Foundation
import TestHelpers
import Testing

@_spi(Experimental) @testable import Storage

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite
struct VectorBucketClientTests {
  let url = URL(string: "http://localhost:54321/storage/v1")!
  let transport = RecordingTransport()

  private func makeSUT() throws -> VectorBucketClient {
    StorageVectorsClient(
      api: try StorageAPI(
        configuration: StorageClient.Configuration(
          url: url,
          headers: [:],
          http: .init(transport: transport))
      )
    ).from("documents")
  }

  @Test
  func createIndex() async throws {
    let bucket = try makeSUT()

    transport.stub(.post, url.appendingPathComponent("vector/CreateIndex"))

    try await bucket.createIndex(
      "embeddings",
      dimension: 1536,
      distanceMetric: .cosine,
      metadataConfiguration: VectorIndexMetadataConfiguration(
        nonFilterableMetadataKeys: ["raw_text"]
      )
    )
  }

  @Test
  func deleteIndex() async throws {
    let bucket = try makeSUT()

    transport.stub(.post, url.appendingPathComponent("vector/DeleteIndex"))

    try await bucket.deleteIndex("embeddings")
  }

  @Test
  func getIndexDecodesVectorIndex() async throws {
    let bucket = try makeSUT()

    transport.stub(
      .post,
      url.appendingPathComponent("vector/GetIndex"),
      data: Data(
        """
        {"index":{"indexName":"embeddings","vectorBucketName":"documents","dataType":"float32",\
        "dimension":1536,"distanceMetric":"cosine","creationTime":1730000000}}
        """.utf8
      )
    )

    let index = try await bucket.index("embeddings")
    #expect(index.indexName == "embeddings")
    #expect(index.vectorBucketName == "documents")
    #expect(index.dataType == .float32)
    #expect(index.dimension == 1536)
    #expect(index.distanceMetric == .cosine)
    #expect(index.creationTime == Date(timeIntervalSince1970: 1_730_000_000))
  }

  @Test
  func listIndexesDecodesIndexesAndNextToken() async throws {
    let bucket = try makeSUT()

    transport.stub(
      .post,
      url.appendingPathComponent("vector/ListIndexes"),
      data: Data(
        """
        {"indexes":[{"indexName":"embeddings","vectorBucketName":"documents"},\
        {"indexName":"summaries","vectorBucketName":"documents"}],"nextToken":"page-2"}
        """.utf8
      )
    )

    let response = try await bucket.listIndexes(
      options: ListIndexesOptions(prefix: "e", pageSize: 2)
    ).page()
    #expect(response.indexes.map(\.indexName) == ["embeddings", "summaries"])
    #expect(response.nextToken == "page-2")
  }

  @Test
  func fromReturnsScopedIndexClient() throws {
    let bucket = try makeSUT()
    let index = bucket.from("embeddings")
    #expect(index.vectorBucketName == "documents")
    #expect(index.indexName == "embeddings")
  }

  @Test
  func forbiddenThrowsStorageError() async throws {
    let bucket = try makeSUT()

    transport.stub(
      .post,
      url.appendingPathComponent("vector/CreateIndex"),
      status: .forbidden,
      data: Data(
        """
        {"code":"403","error":"Unauthorized","message":"new row violates row-level security",\
        "statusCode":"403"}
        """.utf8
      )
    )

    let error = await #expect(throws: StorageError.self) {
      try await bucket.createIndex("embeddings", dimension: 1536, distanceMetric: .cosine)
    }
    #expect(error?.message == "new row violates row-level security")
    #expect(error?.kind == .server)
    #expect(error?.serverError?.error == "Unauthorized")
    #expect(error?.response?.status == 403)
  }
}
