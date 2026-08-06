//
//  VectorIndexClientTests.swift
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
  struct VectorIndexClientTests {
    let url = URL(string: "http://localhost:54321/storage/v1")!

    private func makeSUT() -> VectorIndexClient {
      Mocker.removeAll()

      let configuration = URLSessionConfiguration.ephemeral
      configuration.protocolClasses = [MockingURLProtocol.self]
      let session = URLSession(configuration: configuration)

      return StorageVectorsClient(
        configuration: StorageClientConfiguration(
          url: url,
          headers: [:],
          session: StorageHTTPSession(
            fetch: { try await session.data(for: $0) },
            upload: { try await session.upload(for: $0, from: $1) }
          ),
          logger: nil
        )
      ).from("documents").index("embeddings")
    }

    @Test
    func putVectors() async throws {
      let index = makeSUT()

      Mock(
        url: url.appendingPathComponent("vector/PutVectors"),
        statusCode: 200,
        data: [.post: Data()]
      ).register()

      try await index.putVectors([
        VectorEntry(
          key: "doc-1",
          data: VectorData(float32: [0.1, 0.2, 0.3]),
          metadata: ["title": "Introduction"]
        )
      ])
    }

    @Test
    func deleteVectors() async throws {
      let index = makeSUT()

      Mock(
        url: url.appendingPathComponent("vector/DeleteVectors"),
        statusCode: 200,
        data: [.post: Data()]
      ).register()

      try await index.deleteVectors(keys: ["doc-1", "doc-2"])
    }

    @Test
    func getVectorsDecodesVectors() async throws {
      let index = makeSUT()

      Mock(
        url: url.appendingPathComponent("vector/GetVectors"),
        statusCode: 200,
        data: [
          .post: Data(
            """
            {"vectors":[{"key":"doc-1","data":{"float32":[0.1,0.2,0.3]},"metadata":{"title":"Intro"}}]}
            """.utf8
          )
        ]
      ).register()

      let vectors = try await index.getVectors(
        keys: ["doc-1"], returnData: true, returnMetadata: true)
      #expect(vectors.count == 1)
      #expect(vectors[0].key == "doc-1")
      #expect(vectors[0].data?.float32 == [0.1, 0.2, 0.3])
      #expect(vectors[0].metadata?["title"]?.stringValue == "Intro")
    }

    @Test
    func listVectorsDecodesVectorsAndNextToken() async throws {
      let index = makeSUT()

      Mock(
        url: url.appendingPathComponent("vector/ListVectors"),
        statusCode: 200,
        data: [
          .post: Data(
            """
            {"vectors":[{"key":"doc-1"},{"key":"doc-2"}],"nextToken":"page-2"}
            """.utf8
          )
        ]
      ).register()

      let response = try await index.listVectors(
        maxResults: 2, segment: VectorListSegment(count: 4, index: 0))
      #expect(response.vectors.map(\.key) == ["doc-1", "doc-2"])
      #expect(response.nextToken == "page-2")
    }

    @Test
    func queryVectorsDecodesMatchesAndDistanceMetric() async throws {
      let index = makeSUT()

      Mock(
        url: url.appendingPathComponent("vector/QueryVectors"),
        statusCode: 200,
        data: [
          .post: Data(
            """
            {"vectors":[{"key":"doc-1","distance":0.12},{"key":"doc-2","distance":0.34}],\
            "distanceMetric":"cosine"}
            """.utf8
          )
        ]
      ).register()

      let response = try await index.queryVectors(
        VectorData(float32: [0.1, 0.2, 0.3]),
        topK: 5,
        filter: ["category": "technical"],
        returnDistance: true
      )
      #expect(response.vectors.map(\.key) == ["doc-1", "doc-2"])
      #expect(response.vectors.map(\.distance) == [0.12, 0.34])
      #expect(response.distanceMetric == .cosine)
    }

    @Test
    func forbiddenThrowsStorageError() async throws {
      let index = makeSUT()

      Mock(
        url: url.appendingPathComponent("vector/PutVectors"),
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
        try await index.putVectors([
          VectorEntry(key: "doc-1", data: VectorData(float32: [0.1]))
        ])
      }
      #expect(error?.message == "new row violates row-level security")
      #expect(error?.error == "Unauthorized")
    }
  }
}
