//
//  VectorBucketClientTests.swift
//  Storage
//
//  Created by Guilherme Souza on 06/08/26.
//
import Foundation
import Mocker
import TestHelpers
import Testing

@_spi(Experimental) @testable import Storage

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

extension StorageMockerTests {
  @Suite(.mockerSerialized)
  struct VectorBucketClientTests {
    let url = URL(string: "http://localhost:54321/storage/v1")!

    private func makeSUT() -> VectorBucketClient {
      Mocker.removeAll()

      let configuration = URLSessionConfiguration.ephemeral
      configuration.protocolClasses = [MockingURLProtocol.self]
      let session = URLSession(configuration: configuration)

      return StorageVectorsClient(
        api: StorageApi(
          configuration: StorageClientConfiguration(
            url: url,
            headers: [:],
            session: StorageHTTPSession(
              fetch: { try await session.data(for: $0) },
              upload: { try await session.upload(for: $0, from: $1) }
            ),
            logger: nil
          )
        )
      ).from("documents")
    }

    @Test
    func createIndex() async throws {
      let bucket = makeSUT()

      Mock(
        url: url.appendingPathComponent("vector/CreateIndex"),
        statusCode: 200,
        data: [.post: Data()]
      ).register()

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
      let bucket = makeSUT()

      Mock(
        url: url.appendingPathComponent("vector/DeleteIndex"),
        statusCode: 200,
        data: [.post: Data()]
      ).register()

      try await bucket.deleteIndex("embeddings")
    }

    @Test
    func getIndexDecodesVectorIndex() async throws {
      let bucket = makeSUT()

      Mock(
        url: url.appendingPathComponent("vector/GetIndex"),
        statusCode: 200,
        data: [
          .post: Data(
            """
            {"index":{"indexName":"embeddings","vectorBucketName":"documents","dataType":"float32",\
            "dimension":1536,"distanceMetric":"cosine","creationTime":1730000000}}
            """.utf8
          )
        ]
      ).register()

      let index = try await bucket.getIndex("embeddings")
      #expect(index.indexName == "embeddings")
      #expect(index.vectorBucketName == "documents")
      #expect(index.dataType == .float32)
      #expect(index.dimension == 1536)
      #expect(index.distanceMetric == .cosine)
      #expect(index.creationTime == 1_730_000_000)
    }

    @Test
    func listIndexesDecodesIndexesAndNextToken() async throws {
      let bucket = makeSUT()

      Mock(
        url: url.appendingPathComponent("vector/ListIndexes"),
        statusCode: 200,
        data: [
          .post: Data(
            """
            {"indexes":[{"indexName":"embeddings","vectorBucketName":"documents"},\
            {"indexName":"summaries","vectorBucketName":"documents"}],"nextToken":"page-2"}
            """.utf8
          )
        ]
      ).register()

      let response = try await bucket.listIndexes(prefix: "e", maxResults: 2)
      #expect(response.indexes.map(\.indexName) == ["embeddings", "summaries"])
      #expect(response.nextToken == "page-2")
    }

    @Test
    func indexReturnsScopedClient() {
      let bucket = makeSUT()
      let index = bucket.index("embeddings")
      #expect(index.vectorBucketName == "documents")
      #expect(index.indexName == "embeddings")
    }

    @Test
    func forbiddenThrowsStorageError() async throws {
      let bucket = makeSUT()

      Mock(
        url: url.appendingPathComponent("vector/CreateIndex"),
        statusCode: 403,
        data: [
          .post: Data(
            """
            {"code":"403","error":"Unauthorized","message":"new row violates row-level security",\
            "statusCode":"403"}
            """.utf8
          )
        ]
      ).register()

      let error = await #expect(throws: StorageError.self) {
        try await bucket.createIndex("embeddings", dimension: 1536, distanceMetric: .cosine)
      }
      #expect(error?.message == "new row violates row-level security")
      #expect(error?.error == "Unauthorized")
    }
  }
}
