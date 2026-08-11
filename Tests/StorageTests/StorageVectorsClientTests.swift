//
//  StorageVectorsClientTests.swift
//  Storage
//
//  Created by Guilherme Souza on 27/07/26.
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
  struct StorageVectorsClientTests {
    let url = URL(string: "http://localhost:54321/storage/v1")!

    private func makeSUT() -> StorageVectorsClient {
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
      )
    }

    @Test
    func createBucket() async throws {
      let vectors = makeSUT()

      Mock(
        url: url.appendingPathComponent("vector/CreateVectorBucket"),
        statusCode: 200,
        data: [.post: Data()]
      ).register()

      try await vectors.createBucket("documents")
    }

    @Test
    func deleteBucket() async throws {
      let vectors = makeSUT()

      Mock(
        url: url.appendingPathComponent("vector/DeleteVectorBucket"),
        statusCode: 200,
        data: [.post: Data()]
      ).register()

      try await vectors.deleteBucket("documents")
    }

    @Test
    func getBucketDecodesVectorBucket() async throws {
      let vectors = makeSUT()

      Mock(
        url: url.appendingPathComponent("vector/GetVectorBucket"),
        statusCode: 200,
        data: [
          .post: Data(
            """
            {"vectorBucket":{"vectorBucketName":"documents","creationTime":1730000000}}
            """.utf8
          )
        ]
      ).register()

      let bucket = try await vectors.getBucket("documents")
      #expect(bucket.vectorBucketName == "documents")
      #expect(bucket.creationTime == 1_730_000_000)
    }

    @Test
    func listBucketsDecodesBucketsAndNextToken() async throws {
      let vectors = makeSUT()

      Mock(
        url: url.appendingPathComponent("vector/ListVectorBuckets"),
        statusCode: 200,
        data: [
          .post: Data(
            """
            {"vectorBuckets":[{"vectorBucketName":"documents"},{"vectorBucketName":"images"}],\
            "nextToken":"page-2"}
            """.utf8
          )
        ]
      ).register()

      let response = try await vectors.listBuckets(prefix: "doc", maxResults: 2)
      #expect(response.vectorBuckets.map(\.vectorBucketName) == ["documents", "images"])
      #expect(response.nextToken == "page-2")
    }

    @Test
    func forbiddenThrowsStorageError() async throws {
      let vectors = makeSUT()

      Mock(
        url: url.appendingPathComponent("vector/CreateVectorBucket"),
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
        try await vectors.createBucket("documents")
      }
      #expect(error?.message == "new row violates row-level security")
      #expect(error?.error == "Unauthorized")
    }
  }
}
