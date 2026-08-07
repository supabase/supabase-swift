//
//  AnalyticsClientIntegrationTests.swift
//
//
//  Created by Guilherme Souza on 06/08/26.
//

import Foundation
@_spi(Experimental) import Storage
import Testing

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

// Gated behind a separate opt-in flag (not `INTEGRATION_TESTS`): analytics/Iceberg support
// requires `ICEBERG_ENABLED=true` plus catalog/shard/warehouse configuration on the storage
// backend that the Supabase CLI's local dev stack (`supabase start`) doesn't set up by default —
// hitting these endpoints there 404s at the gateway rather than reaching the route. Run this
// suite manually against a backend with Iceberg support enabled via
// `ICEBERG_INTEGRATION_TESTS=1 swift test --filter AnalyticsClientIntegrationTests`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["ICEBERG_INTEGRATION_TESTS"] != nil))
final class AnalyticsClientIntegrationTests {
  let analytics = SupabaseStorageClient(
    configuration: StorageClientConfiguration(
      url: URL(string: "\(DotEnv.SUPABASE_URL)/storage/v1")!,
      headers: [
        "Authorization": "Bearer \(DotEnv.SUPABASE_SECRET_KEY)"
      ],
      logger: nil
    )
  ).analytics

  var bucketName = ""

  init() async throws {
    bucketName = "test-analytics-bucket-\(UUID().uuidString)"
    _ = try await analytics.createBucket(bucketName)
  }

  // Async cleanup can outlive the test if the process exits immediately after — acceptable for
  // local dev/CI cleanup, not correctness-critical.
  deinit {
    let analytics = analytics
    let bucketName = bucketName
    Task {
      let bucket = analytics.from(bucketName)
      if let namespaces = try? await bucket.listNamespaces() {
        for name in namespaces.namespaces {
          let namespace = bucket.namespace(name)
          if let tables = try? await namespace.listTables() {
            for table in tables.tables {
              try? await namespace.deleteTable(table, purge: true)
            }
          }
          try? await bucket.deleteNamespace(name)
        }
      }
      try? await analytics.deleteBucket(bucketName)
    }
  }

  @Test
  func namespace_CRUD() async throws {
    let bucket = analytics.from(bucketName)
    let namespaceName = "test_namespace"

    var page = try await bucket.listNamespaces()
    #expect(!page.namespaces.contains(namespaceName))

    let created = try await bucket.createNamespace(namespaceName, properties: ["owner": "sdk-test"])
    #expect(created.name == namespaceName)
    #expect(created.properties?["owner"] == "sdk-test")

    #expect(try await bucket.namespaceExists(namespaceName) == true)
    #expect(try await bucket.namespaceExists("does-not-exist") == false)

    let loaded = try await bucket.getNamespace(namespaceName)
    #expect(loaded.name == namespaceName)

    page = try await bucket.listNamespaces()
    #expect(page.namespaces.contains(namespaceName))

    try await bucket.deleteNamespace(namespaceName)

    page = try await bucket.listNamespaces()
    #expect(!page.namespaces.contains(namespaceName))
  }

  @Test
  func table_CRUD() async throws {
    let bucket = analytics.from(bucketName)
    let namespaceName = "test_namespace"
    _ = try await bucket.createNamespace(namespaceName)
    let namespace = bucket.namespace(namespaceName)
    let tableName = "test_table"

    var page = try await namespace.listTables()
    #expect(!page.tables.contains(tableName))

    let created = try await namespace.createTable(
      tableName,
      schema: IcebergSchema(fields: [
        IcebergStructField(id: 1, name: "id", type: "long", required: true),
        IcebergStructField(id: 2, name: "name", type: "string", required: false),
      ])
    )
    #expect(created.metadata.tableUUID.isEmpty == false)
    #expect(created.metadata.schemas?.first?.fields.count == 2)

    #expect(try await namespace.tableExists(tableName) == true)
    #expect(try await namespace.tableExists("does-not-exist") == false)

    let loaded = try await namespace.getTable(tableName)
    #expect(loaded.metadata.tableUUID == created.metadata.tableUUID)

    page = try await namespace.listTables()
    #expect(page.tables.contains(tableName))

    try await namespace.deleteTable(tableName, purge: true)

    page = try await namespace.listTables()
    #expect(!page.tables.contains(tableName))
  }
}
