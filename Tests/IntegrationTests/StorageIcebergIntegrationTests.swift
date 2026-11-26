//
//  StorageIcebergIntegrationTests.swift
//  IntegrationTests
//
//  Created by Guilherme Souza on 25/11/26.
//

import Foundation
@_spi(Experimental) import Storage
@_spi(Experimental) import StorageIceberg
import Testing

@Suite(.enabled(if: ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil))
struct StorageIcebergIntegrationTests {
  let analytics = StorageIntegration.admin.analytics

  @Test(.enabled(if: StorageIntegration.hasTestFeatures))
  func catalogLifeCycle() async throws {
    let bucket = "iceberg-\(UUID().uuidString.lowercased().prefix(8))"
    try await analytics.createBucket(bucket)
    let catalog = analytics.catalog(bucket: bucket)

    do {
      try await exerciseCatalog(catalog)
    } catch {
      await dropCatalog(catalog)
      throw error
    }
    await dropCatalog(catalog)
  }

  @Test(.enabled(if: !StorageIntegration.hasTestFeatures))
  func aStackWithoutIcebergRefusesTheCatalog() async throws {
    let error = await StorageIntegration.storageError {
      _ = try await analytics.catalog(bucket: "missing").listNamespaces()
    }

    #expect(error?.kind == .server)
    #expect(error?.isNotFound == true)
  }

  private func exerciseCatalog(_ catalog: IcebergCatalog) async throws {
    try await catalog.createNamespace("sales", properties: ["owner": "it"])
    #expect(try await catalog.namespaceExists("sales"))
    #expect(try await catalog.namespaceExists("nope") == false)
    #expect(try await catalog.listNamespaces() == ["sales"])
    #expect(try await catalog.namespaceProperties("sales")["owner"] == "it")

    let creation = IcebergTableCreation(
      name: "orders",
      schema: IcebergSchema(fields: [
        IcebergField(id: 1, name: "id", type: .long, isRequired: true),
        IcebergField(id: 2, name: "name", type: .string, isRequired: false),
      ]),
      partitionSpec: IcebergPartitionSpec(
        specID: 0,
        fields: [IcebergPartitionField(sourceID: 1, name: "id", transform: .identity)]
      )
    )
    try await catalog.createTable(creation, in: "sales")

    #expect(
      try await catalog.listTables(in: "sales").contains(
        IcebergTableIdentifier(namespace: "sales", name: "orders")))

    let metadata = try await catalog.table("orders", in: "sales").metadata
    #expect(metadata.currentSchema?.fields.map(\.name) == ["id", "name"])
    let defaultSpec = metadata.partitionSpecs.first { $0.specID == metadata.defaultSpecID }
    #expect(defaultSpec?.fields.count == 1)

    #expect(try await catalog.tableExists("orders", in: "sales"))
    #expect(try await catalog.tableExists("nope", in: "sales") == false)

    let committed = try await catalog.updateTable(
      "orders", in: "sales", updates: [.setProperties(["comment": "it"])])
    #expect(committed.metadata.properties["comment"] == "it")

    let staleCommit = await StorageIntegration.storageError {
      try await catalog.updateTable(
        "orders", in: "sales",
        requirements: [.assertCurrentSchemaID(99)],
        updates: [.setProperties(["comment": "stale"])])
    }
    #expect(staleCommit?.kind == .server)
    #expect(staleCommit?.code?.rawValue == "CommitFailedException")

    let notEmpty = await StorageIntegration.storageError {
      try await catalog.deleteNamespace("sales")
    }
    #expect(notEmpty?.kind == .server)
    #expect(notEmpty?.code?.rawValue == "IcebergResourceNotEmpty")
    #expect(notEmpty?.serverError?.statusCode == 400)

    try await catalog.deleteTable("orders", in: "sales", purge: true)
    try await catalog.deleteNamespace("sales")
    #expect(try await catalog.namespaceExists("sales") == false)
  }

  /// Removes what the run left behind, then the bucket. Each step ignores errors, since the
  /// run may have removed the table or the namespace already.
  private func dropCatalog(_ catalog: IcebergCatalog) async {
    try? await catalog.deleteTable("orders", in: "sales", purge: true)
    try? await catalog.deleteNamespace("sales")
    try? await analytics.deleteBucket(catalog.bucket)
  }
}
