//
//  VectorIndexClientTests.swift
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
struct VectorIndexClientTests {
  let url = URL(string: "http://localhost:54321/storage/v1")!
  let transport = RecordingTransport()

  private func makeSUT() throws -> VectorIndexClient {
    StorageVectorsClient(
      api: try StorageAPI(
        configuration: StorageClient.Configuration(
          url: url,
          headers: [:],
          http: .init(transport: transport))
      )
    ).from("documents").from("embeddings")
  }

  @Test
  func putVectors() async throws {
    let index = try makeSUT()

    transport.stub(.post, url.appendingPathComponent("vector/PutVectors"))

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
    let index = try makeSUT()

    transport.stub(.post, url.appendingPathComponent("vector/DeleteVectors"))

    try await index.deleteVectors(keys: ["doc-1", "doc-2"])
  }

  @Test
  func getVectorsDecodesVectors() async throws {
    let index = try makeSUT()

    transport.stub(
      .post,
      url.appendingPathComponent("vector/GetVectors"),
      data: Data(
        """
        {"vectors":[{"key":"doc-1","data":{"float32":[0.1,0.2,0.3]},"metadata":{"title":"Intro"}}]}
        """.utf8
      )
    )

    let vectors = try await index.vectors(
      keys: ["doc-1"], options: GetVectorsOptions(returnData: true, returnMetadata: true))
    #expect(vectors.count == 1)
    #expect(vectors[0].key == "doc-1")
    #expect(vectors[0].data?.float32 == [0.1, 0.2, 0.3])
    #expect(vectors[0].metadata?["title"]?.stringValue == "Intro")
  }

  @Test
  func listVectorsDecodesVectorsAndNextToken() async throws {
    let index = try makeSUT()

    transport.stub(
      .post,
      url.appendingPathComponent("vector/ListVectors"),
      data: Data(
        """
        {"vectors":[{"key":"doc-1"},{"key":"doc-2"}],"nextToken":"page-2"}
        """.utf8
      )
    )

    let response = try await index.listVectors(
      options: ListVectorsOptions(pageSize: 2, segment: VectorListSegment(count: 4, index: 0))
    ).page()
    #expect(response.vectors.map(\.key) == ["doc-1", "doc-2"])
    #expect(response.nextToken == "page-2")
  }

  @Test
  func queryVectorsDecodesMatchesAndDistanceMetric() async throws {
    let index = try makeSUT()

    transport.stub(
      .post,
      url.appendingPathComponent("vector/QueryVectors"),
      data: Data(
        """
        {"vectors":[{"key":"doc-1","distance":0.12},{"key":"doc-2","distance":0.34}],\
        "distanceMetric":"cosine"}
        """.utf8
      )
    )

    let response = try await index.queryVectors(
      VectorData(float32: [0.1, 0.2, 0.3]), topK: 5,
      options: QueryVectorsOptions(filter: ["category": "technical"], returnDistance: true))
    #expect(response.vectors.map(\.key) == ["doc-1", "doc-2"])
    #expect(response.vectors.map(\.distance) == [0.12, 0.34])
    #expect(response.distanceMetric == .cosine)
  }

  @Test
  func forbiddenThrowsStorageError() async throws {
    let index = try makeSUT()

    transport.stub(
      .post,
      url.appendingPathComponent("vector/PutVectors"),
      status: .forbidden,
      data: Data(
        """
        {"code":"403","error":"Unauthorized","message":"new row violates row-level security",\
        "statusCode":"403"}
        """.utf8
      )
    )

    let error = await #expect(throws: StorageError.self) {
      try await index.putVectors([
        VectorEntry(key: "doc-1", data: VectorData(float32: [0.1]))
      ])
    }
    #expect(error?.message == "new row violates row-level security")
    #expect(error?.kind == .server)
    #expect(error?.serverError?.error == "Unauthorized")
    #expect(error?.response?.status == 403)
  }
}
