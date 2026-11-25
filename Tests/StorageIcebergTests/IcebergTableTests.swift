//
//  IcebergTableTests.swift
//  StorageIceberg
//
//  Created by Guilherme Souza on 25/11/26.
//

import ConcurrencyExtras
import Foundation
import HTTPTypes
import Helpers
import TestHelpers
import Testing

@_spi(Experimental) import Storage
@_spi(Experimental) import StorageIceberg

@Suite
struct IcebergTableTests {
  @Test
  func createTablePostsTheDefinition() async throws {
    let sent = LockIsolated<[Sent]>([])
    let catalog = try makeCatalog(sent: sent, response: try fixture("load-table"))

    let table = try await catalog.createTable(
      IcebergTableCreation(
        name: "orders",
        schema: IcebergSchema(fields: [
          IcebergField(id: 1, name: "id", type: .long, isRequired: true),
          IcebergField(id: 2, name: "name", type: .string, isRequired: false),
        ]),
        partitionSpec: IcebergPartitionSpec(
          specID: 0,
          fields: [IcebergPartitionField(sourceID: 1, name: "id", transform: .identity)])
      ),
      in: "sales"
    )

    let request = try #require(sent.value.first)
    #expect(request.request.method == .post)
    #expect(request.request.path == "/storage/v1/iceberg/v1/events/namespaces/sales/tables")
    #expect(request.request.headerFields[.contentType] == "application/json")
    #expect(
      try jsonEqual(
        request.body,
        #"""
        {
          "name": "orders",
          "schema": {
            "type": "struct",
            "fields": [
              {"id": 1, "name": "id", "type": "long", "required": true},
              {"id": 2, "name": "name", "type": "string", "required": false}
            ]
          },
          "partition-spec": {
            "spec-id": 0,
            "fields": [{"source-id": 1, "name": "id", "transform": "identity"}]
          },
          "properties": {}
        }
        """#))
    #expect(
      table.metadataLocation
        == "file:/tmp/warehouse/stub_f5725618_df77_440a_80da_fb49efe14555/t2/metadata/00000-b5ad038d-cb20-4d9d-b301-23f6f4f63103.metadata.json"
    )
    #expect(table.metadata.tableUUID == "9999397f-3aa0-4d28-b1d7-4f8e25a86054")
    #expect(
      table.metadata.partitionSpecs == [
        IcebergPartitionSpec(
          specID: 0,
          fields: [
            IcebergPartitionField(fieldID: 1000, sourceID: 1, name: "id", transform: .identity)
          ])
      ])
  }

  @Test
  func listTablesReturnsIdentifiers() async throws {
    let sent = LockIsolated<[Sent]>([])
    let catalog = try makeCatalog(
      sent: sent, response: #"{"identifiers":[{"namespace":["sales"],"name":"orders"}]}"#)

    #expect(
      try await catalog.listTables(in: "sales") == [
        IcebergTableIdentifier(namespace: "sales", name: "orders")
      ])
    #expect(sent.value.map(\.request.method) == [.get])
    #expect(
      sent.value.map(\.request.path) == ["/storage/v1/iceberg/v1/events/namespaces/sales/tables"])

    let empty = try makeCatalog(response: "{}")
    #expect(try await empty.listTables(in: "sales") == [])
  }

  @Test
  func tableLoadsMetadata() async throws {
    let sent = LockIsolated<[Sent]>([])
    let catalog = try makeCatalog(sent: sent, response: try fixture("load-table"))

    let table = try await catalog.table("orders", in: "sales")

    #expect(sent.value.map(\.request.method) == [.get])
    #expect(
      sent.value.map(\.request.path) == [
        "/storage/v1/iceberg/v1/events/namespaces/sales/tables/orders"
      ])
    #expect(table.config == [:])
    let metadata = table.metadata
    #expect(metadata.formatVersion == 2)
    #expect(metadata.currentSchema?.fields.count == 2)
    #expect(metadata.currentSchemaID == 0)
    #expect(metadata.lastUpdatedMilliseconds == 1_795_632_563_602)
    #expect(metadata.properties == ["write.parquet.compression-codec": "zstd"])
    #expect(metadata.defaultSpecID == 0)
    #expect(metadata.sortOrders == [IcebergSortOrder(orderID: 0, fields: [])])
    #expect(metadata.defaultSortOrderID == 0)
    #expect(metadata.currentSnapshotID == -1)
    #expect(metadata.raw["last-partition-id"] == 1000)

    let configured = try makeCatalog(
      response: #"{"metadata":{"format-version":2},"config":{"token":"t"}}"#)
    let withConfig = try await configured.table("orders", in: "sales")
    #expect(withConfig.config == ["token": "t"])
    #expect(withConfig.metadataLocation == nil)
    #expect(withConfig.metadata.schemas == [])
    #expect(withConfig.metadata.properties == [:])
    #expect(withConfig.metadata.currentSchema == nil)
  }

  @Test
  func aLargeSnapshotIDStaysExact() async throws {
    let catalog = try makeCatalog(
      response: #"{"metadata":{"format-version":2,"current-snapshot-id":9007199254740993}}"#)

    let metadata = try await catalog.table("orders", in: "sales").metadata

    #expect(metadata.currentSnapshotID == 9_007_199_254_740_993)
    let raw = try #require(metadata.raw["current-snapshot-id"])
    #expect(String(decoding: try JSONEncoder().encode(raw), as: UTF8.self) == "9007199254740993")
  }

  @Test
  func tableExistsIsTrueOn204AndFalseOn404() async throws {
    let sent = LockIsolated<[Sent]>([])
    let present = try makeCatalog(sent: sent, status: .noContent, response: "")
    let missing = try makeCatalog(status: .notFound, response: "")

    #expect(try await present.tableExists("orders", in: "sales") == true)
    #expect(try await missing.tableExists("orders", in: "sales") == false)
    #expect(sent.value.map(\.request.method) == [.head])
    #expect(
      sent.value.map(\.request.path) == [
        "/storage/v1/iceberg/v1/events/namespaces/sales/tables/orders"
      ])
  }

  @Test
  func tableExistsThrowsOnServerError() async throws {
    let catalog = try makeCatalog(
      status: .forbidden,
      response: #"""
        {"error":{"message":"Forbidden","type":"ForbiddenException","code":403}}
        """#)

    let error = try await #require(throws: StorageError.self) {
      try await catalog.tableExists("orders", in: "sales")
    }
    #expect(error.response?.status == .forbidden)
  }

  @Test
  func createTableSendsWriteOrderAndLocation() async throws {
    let sent = LockIsolated<[Sent]>([])
    let catalog = try makeCatalog(sent: sent, response: try fixture("load-table"))

    try await catalog.createTable(
      IcebergTableCreation(
        name: "orders",
        schema: IcebergSchema(fields: [
          IcebergField(id: 1, name: "id", type: .long, isRequired: true)
        ]),
        writeOrder: IcebergSortOrder(
          orderID: 1,
          fields: [
            IcebergSortField(
              sourceID: 1, transform: .identity, direction: .descending, nullOrder: .nullsLast)
          ]),
        location: "s3://events/orders"
      ),
      in: "sales"
    )

    #expect(
      try jsonEqual(
        sent.value.first?.body,
        #"""
        {
          "name": "orders",
          "schema": {
            "type": "struct",
            "fields": [{"id": 1, "name": "id", "type": "long", "required": true}]
          },
          "write-order": {
            "order-id": 1,
            "fields": [
              {
                "source-id": 1, "transform": "identity",
                "direction": "desc", "null-order": "nulls-last"
              }
            ]
          },
          "properties": {},
          "location": "s3://events/orders"
        }
        """#))
  }

  @Test
  func aNestedNamespaceJoinsItsLevelsWithADot() async throws {
    let catalog = try makeCatalog(
      response: #"{"identifiers":[{"namespace":["a","b"],"name":"orders"}]}"#)

    #expect(
      try await catalog.listTables(in: "a") == [
        IcebergTableIdentifier(namespace: "a.b", name: "orders")
      ])
  }

  @Test
  func deleteTableSendsPurge() async throws {
    let sent = LockIsolated<[Sent]>([])
    let catalog = try makeCatalog(sent: sent, status: .noContent, response: "")

    try await catalog.deleteTable("orders", in: "sales")
    try await catalog.deleteTable("orders", in: "sales", purge: true)

    #expect(sent.value.map(\.request.method) == [.delete, .delete])
    #expect(
      sent.value.map(\.request.path) == [
        "/storage/v1/iceberg/v1/events/namespaces/sales/tables/orders?purgeRequested=false",
        "/storage/v1/iceberg/v1/events/namespaces/sales/tables/orders?purgeRequested=true",
      ])
  }

  @Test
  func tableNamesStayOnePathSegment() async throws {
    let sent = LockIsolated<[Sent]>([])
    let catalog = try makeCatalog(sent: sent, status: .noContent, response: "")

    _ = try await catalog.tableExists("a/b", in: "x y")
    try await catalog.deleteTable("a/b c", in: "sales")
    _ = try await catalog.tableExists("100%", in: "café")

    #expect(
      sent.value.map(\.request.path) == [
        "/storage/v1/iceberg/v1/events/namespaces/x%20y/tables/a%2Fb",
        "/storage/v1/iceberg/v1/events/namespaces/sales/tables/a%2Fb%20c?purgeRequested=false",
        "/storage/v1/iceberg/v1/events/namespaces/caf%C3%A9/tables/100%25",
      ])
  }

  @Test
  func aSpecInANewerShapeIsLeftOutOfTheTypedMetadata() throws {
    let json = #"""
      {
        "format-version": 3,
        "partition-specs": [
          {"spec-id": 0, "fields": []},
          {"spec-id": 1, "fields": [
            {"source-ids": [1, 2], "field-id": 1000, "name": "b", "transform": "bucket[4]"}
          ]}
        ],
        "sort-orders": [
          {"order-id": 1, "fields": [
            {"source-ids": [1, 2], "transform": "bucket[4]", "direction": "asc",
             "null-order": "nulls-first"}
          ]}
        ]
      }
      """#

    let metadata = try JSONDecoder().decode(IcebergTableMetadata.self, from: Data(json.utf8))

    #expect(metadata.partitionSpecs == [IcebergPartitionSpec(specID: 0, fields: [])])
    #expect(metadata.sortOrders.isEmpty)
    guard case .array(let specs)? = metadata.raw["partition-specs"] else {
      Issue.record("raw has no partition-specs array")
      return
    }
    #expect(specs.count == 2)
  }
}

/// The text of the JSON fixture `name` in the test bundle.
private func fixture(_ name: String) throws -> String {
  let url = try #require(Bundle.module.url(forResource: name, withExtension: "json"))
  return try String(contentsOf: url, encoding: .utf8)
}
