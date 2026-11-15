//
//  StorageVectorsClientTests.swift
//  Storage
//
//  Created by Guilherme Souza on 27/07/26.
//
import Foundation
import TestHelpers
import Testing

@_spi(Experimental) @testable import Storage

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite
struct StorageVectorsClientTests {
  let url = URL(string: "http://localhost:54321/storage/v1")!
  let transport = RecordingTransport()

  private func makeSUT() throws -> StorageVectorsClient {
    StorageVectorsClient(
      api: try StorageAPI(
        configuration: StorageClient.Configuration(
          url: url,
          headers: [:],
          http: .init(transport: transport))
      )
    )
  }

  @Test
  func createBucket() async throws {
    let vectors = try makeSUT()

    transport.stub(.post, url.appendingPathComponent("vector/CreateVectorBucket"))

    try await vectors.createBucket("documents")
  }

  @Test
  func deleteBucket() async throws {
    let vectors = try makeSUT()

    transport.stub(.post, url.appendingPathComponent("vector/DeleteVectorBucket"))

    try await vectors.deleteBucket("documents")
  }

  @Test
  func getBucketDecodesVectorBucket() async throws {
    let vectors = try makeSUT()

    transport.stub(
      .post,
      url.appendingPathComponent("vector/GetVectorBucket"),
      data: Data(
        """
        {"vectorBucket":{"vectorBucketName":"documents","creationTime":1730000000}}
        """.utf8
      )
    )

    let bucket = try await vectors.bucket("documents")
    #expect(bucket.vectorBucketName == "documents")
    #expect(bucket.creationTime == Date(timeIntervalSince1970: 1_730_000_000))
  }

  @Test
  func listBucketsDecodesBucketsAndNextToken() async throws {
    let vectors = try makeSUT()

    transport.stub(
      .post,
      url.appendingPathComponent("vector/ListVectorBuckets"),
      data: Data(
        """
        {"vectorBuckets":[{"vectorBucketName":"documents"},{"vectorBucketName":"images"}],\
        "nextToken":"page-2"}
        """.utf8
      )
    )

    let response = try await vectors.listBuckets(
      options: ListVectorBucketsOptions(prefix: "doc", pageSize: 2)
    ).page()
    #expect(response.vectorBuckets.map(\.vectorBucketName) == ["documents", "images"])
    #expect(response.nextToken == "page-2")
  }

  @Test
  func forbiddenThrowsStorageError() async throws {
    let vectors = try makeSUT()

    transport.stub(
      .post,
      url.appendingPathComponent("vector/CreateVectorBucket"),
      status: .forbidden,
      data: Data(
        """
        {"code":"403","error":"Unauthorized","message":"new row violates row-level security",\
        "statusCode":"403"}
        """.utf8
      )
    )

    let error = await #expect(throws: StorageError.self) {
      try await vectors.createBucket("documents")
    }
    #expect(error?.message == "new row violates row-level security")
    #expect(error?.kind == .server)
    #expect(error?.serverError?.error == "Unauthorized")
    #expect(error?.response?.status == 403)
  }
}
