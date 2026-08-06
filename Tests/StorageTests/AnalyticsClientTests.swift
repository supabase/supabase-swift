//
//  AnalyticsClientTests.swift
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
  struct AnalyticsClientTests {
    let url = URL(string: "http://localhost:54321/storage/v1")!

    private func makeSUT() -> AnalyticsClient {
      Mocker.removeAll()

      let configuration = URLSessionConfiguration.ephemeral
      configuration.protocolClasses = [MockingURLProtocol.self]
      let session = URLSession(configuration: configuration)

      return AnalyticsClient(
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
    func createBucketDecodesBucket() async throws {
      let analytics = makeSUT()

      Mock(
        url: url.appendingPathComponent("iceberg/bucket"),
        statusCode: 200,
        data: [
          .post: Data(
            """
            {"id":"events","name":"events","created_at":"2024-01-01T00:00:00.000Z",\
            "updated_at":"2024-01-01T00:00:00.000Z"}
            """.utf8
          )
        ]
      ).register()

      let bucket = try await analytics.createBucket("events")
      #expect(bucket.id == "events")
      #expect(bucket.name == "events")
    }

    @Test
    func deleteBucket() async throws {
      let analytics = makeSUT()

      Mock(
        url: url.appendingPathComponent("iceberg/bucket/events"),
        statusCode: 200,
        data: [
          .delete: Data(
            """
            {"message":"Successfully deleted"}
            """.utf8)
        ]
      ).register()

      try await analytics.deleteBucket("events")
    }

    @Test
    func listBucketsDecodesArray() async throws {
      let analytics = makeSUT()

      Mock(
        url: url.appendingPathComponent("iceberg/bucket"),
        ignoreQuery: true,
        statusCode: 200,
        data: [
          .get: Data(
            """
            [{"id":"events","name":"events","created_at":"2024-01-01T00:00:00.000Z",\
            "updated_at":"2024-01-01T00:00:00.000Z"}]
            """.utf8
          )
        ]
      ).register()

      let buckets = try await analytics.listBuckets(sortColumn: .createdAt, sortOrder: .descending)
      #expect(buckets.map(\.name) == ["events"])
    }

    @Test
    func fromReturnsScopedClient() {
      let analytics = makeSUT()
      let bucket = analytics.from("events")
      #expect(bucket.bucketName == "events")
    }

    @Test
    func forbiddenThrowsStorageErrorWithNestedShape() async throws {
      let analytics = makeSUT()

      Mock(
        url: url.appendingPathComponent("iceberg/bucket"),
        statusCode: 403,
        data: [
          .post: Data(
            """
            {"error":{"message":"new row violates row-level security","type":"Unauthorized","code":403}}
            """.utf8
          )
        ]
      ).register()

      let error = await #expect(throws: StorageError.self) {
        try await analytics.createBucket("events")
      }
      #expect(error?.message == "new row violates row-level security")
      #expect(error?.error == "Unauthorized")
      #expect(error?.statusCode == "403")
    }
  }
}
