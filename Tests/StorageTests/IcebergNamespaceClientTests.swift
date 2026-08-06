//
//  IcebergNamespaceClientTests.swift
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
  struct IcebergNamespaceClientTests {
    let url = URL(string: "http://localhost:54321/storage/v1")!

    private func makeSUT() -> IcebergNamespaceClient {
      Mocker.removeAll()

      let configuration = URLSessionConfiguration.ephemeral
      configuration.protocolClasses = [MockingURLProtocol.self]
      let session = URLSession(configuration: configuration)

      return AnalyticsClient(
        configuration: StorageClientConfiguration(
          url: url,
          headers: [:],
          session: StorageHTTPSession(
            fetch: { try await session.data(for: $0) },
            upload: { try await session.upload(for: $0, from: $1) }
          ),
          logger: nil
        )
      ).from("events").namespace("default")
    }

    private static let loadTableResultJSON = """
      {"metadata-location":"s3://events/default/clicks/metadata/00000-abc.json",\
      "metadata":{"format-version":2,"table-uuid":"abc-123",\
      "location":"s3://events/default/clicks","last-updated-ms":1700000000000,\
      "properties":{"owner":"team"},\
      "schemas":[{"type":"struct","fields":[\
      {"id":1,"name":"id","type":"long","required":true},\
      {"id":2,"name":"url","type":"string","required":false}],"schema-id":0}],\
      "current-schema-id":0,\
      "partition-specs":[{"spec-id":0,"fields":[]}],\
      "default-spec-id":0}}
      """

    @Test
    func createTableDecodesLoadTableResult() async throws {
      let namespace = makeSUT()

      Mock(
        url: url.appendingPathComponent("iceberg/v1/events/namespaces/default/tables"),
        statusCode: 200,
        data: [.post: Data(Self.loadTableResultJSON.utf8)]
      ).register()

      let result = try await namespace.createTable(
        "clicks",
        schema: IcebergSchema(fields: [
          IcebergStructField(id: 1, name: "id", type: "long", required: true),
          IcebergStructField(id: 2, name: "url", type: "string", required: false),
        ])
      )
      #expect(result.metadataLocation == "s3://events/default/clicks/metadata/00000-abc.json")
      #expect(result.metadata.formatVersion == 2)
      #expect(result.metadata.tableUUID == "abc-123")
      #expect(result.metadata.schemas?.first?.fields.count == 2)
      #expect(result.metadata.lastUpdatedAt == 1_700_000_000)
    }

    @Test
    func getTableDecodesLoadTableResult() async throws {
      let namespace = makeSUT()

      Mock(
        url: url.appendingPathComponent("iceberg/v1/events/namespaces/default/tables/clicks"),
        statusCode: 200,
        data: [.get: Data(Self.loadTableResultJSON.utf8)]
      ).register()

      let result = try await namespace.getTable("clicks")
      #expect(result.metadata.tableUUID == "abc-123")
    }

    @Test
    func listTablesDecodesNamesAndNextPageToken() async throws {
      let namespace = makeSUT()

      Mock(
        url: url.appendingPathComponent("iceberg/v1/events/namespaces/default/tables"),
        ignoreQuery: true,
        statusCode: 200,
        data: [
          .get: Data(
            """
            {"identifiers":[{"name":"clicks","namespace":["default"]},\
            {"name":"impressions","namespace":["default"]}],"next-page-token":"page-2"}
            """.utf8
          )
        ]
      ).register()

      let response = try await namespace.listTables(pageSize: 2)
      #expect(response.tables == ["clicks", "impressions"])
      #expect(response.nextPageToken == "page-2")
    }

    @Test
    func tableExistsReturnsTrue() async throws {
      let namespace = makeSUT()

      Mock(
        url: url.appendingPathComponent("iceberg/v1/events/namespaces/default/tables/clicks"),
        statusCode: 204,
        data: [.head: Data()]
      ).register()

      #expect(try await namespace.tableExists("clicks") == true)
    }

    @Test
    func tableExistsReturnsFalseOn404() async throws {
      let namespace = makeSUT()

      Mock(
        url: url.appendingPathComponent("iceberg/v1/events/namespaces/default/tables/missing"),
        statusCode: 404,
        data: [
          .head: Data(
            """
            {"error":{"message":"table not found","type":"NoSuchTableException","code":404}}
            """.utf8
          )
        ]
      ).register()

      #expect(try await namespace.tableExists("missing") == false)
    }

    @Test
    func deleteTablePassesPurgeRequested() async throws {
      let namespace = makeSUT()

      Mock(
        url: url.appendingPathComponent("iceberg/v1/events/namespaces/default/tables/clicks"),
        ignoreQuery: true,
        statusCode: 204,
        data: [.delete: Data()]
      ).register()

      try await namespace.deleteTable("clicks", purge: true)
    }
  }
}
