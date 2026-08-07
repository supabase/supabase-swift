//
//  AnalyticsBucketClientTests.swift
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
  struct AnalyticsBucketClientTests {
    let url = URL(string: "http://localhost:54321/storage/v1")!

    private func makeSUT() -> AnalyticsBucketClient {
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
      ).from("events")
    }

    @Test
    func createNamespaceDecodesNamespace() async throws {
      let bucket = makeSUT()

      Mock(
        url: url.appendingPathComponent("iceberg/v1/events/namespaces"),
        statusCode: 200,
        data: [
          .post: Data(
            """
            {"namespace":["default"],"properties":{"owner":"team"}}
            """.utf8
          )
        ]
      ).register()

      let namespace = try await bucket.createNamespace("default", properties: ["owner": "team"])
      #expect(namespace.name == "default")
      #expect(namespace.properties?["owner"] == "team")
    }

    @Test
    func getNamespaceDecodesNamespace() async throws {
      let bucket = makeSUT()

      Mock(
        url: url.appendingPathComponent("iceberg/v1/events/namespaces/default"),
        statusCode: 200,
        data: [
          .get: Data(
            """
            {"namespace":["default"],"properties":{}}
            """.utf8
          )
        ]
      ).register()

      let namespace = try await bucket.getNamespace("default")
      #expect(namespace.name == "default")
    }

    @Test
    func listNamespacesDecodesNamesAndNextPageToken() async throws {
      let bucket = makeSUT()

      Mock(
        url: url.appendingPathComponent("iceberg/v1/events/namespaces"),
        ignoreQuery: true,
        statusCode: 200,
        data: [
          .get: Data(
            """
            {"namespaces":[["default"],["prod"]],"next-page-token":"page-2"}
            """.utf8
          )
        ]
      ).register()

      let response = try await bucket.listNamespaces(pageSize: 2)
      #expect(response.namespaces == ["default", "prod"])
      #expect(response.nextPageToken == "page-2")
    }

    @Test
    func namespaceExistsReturnsTrue() async throws {
      let bucket = makeSUT()

      Mock(
        url: url.appendingPathComponent("iceberg/v1/events/namespaces/default"),
        statusCode: 204,
        data: [.head: Data()]
      ).register()

      #expect(try await bucket.namespaceExists("default") == true)
    }

    @Test
    func namespaceExistsReturnsFalseOn404() async throws {
      let bucket = makeSUT()

      Mock(
        url: url.appendingPathComponent("iceberg/v1/events/namespaces/missing"),
        statusCode: 404,
        data: [
          .head: Data(
            """
            {"error":{"message":"namespace not found","type":"NoSuchNamespaceException","code":404}}
            """.utf8
          )
        ]
      ).register()

      #expect(try await bucket.namespaceExists("missing") == false)
    }

    @Test
    func deleteNamespace() async throws {
      let bucket = makeSUT()

      Mock(
        url: url.appendingPathComponent("iceberg/v1/events/namespaces/default"),
        statusCode: 204,
        data: [.delete: Data()]
      ).register()

      try await bucket.deleteNamespace("default")
    }

    @Test
    func namespaceReturnsScopedClient() {
      let bucket = makeSUT()
      let namespace = bucket.namespace("default")
      #expect(namespace.bucketName == "events")
      #expect(namespace.namespaceName == "default")
    }
  }
}
