//
//  StorageIcebergIsolationTests.swift
//  DefaultIsolationTests
//
//  Created by Guilherme Souza on 25/11/26.
//

@_spi(Experimental) import StorageIceberg
@_spi(Experimental) import Supabase

/// Calls every public async StorageIceberg API from the main actor, since this target compiles
/// with `.defaultIsolation(MainActor.self)`. Nothing here runs: if a call stops compiling, the
/// build fails. `scripts/check-isolation-coverage.sh` checks that each API has a call.
enum StorageIcebergIsolationTests {
  static func namespaces(_ catalog: IcebergCatalog) async throws {
    _ = try await catalog.createNamespace("sales")
    _ = try await catalog.createNamespace("sales", properties: ["owner": "team"])
    _ = try await catalog.listNamespaces()
    _ = try await catalog.namespaceProperties("sales")
    _ = try await catalog.namespaceExists("sales")
    try await catalog.deleteNamespace("sales")
  }

  static func tables(_ storage: StorageClient, _ creation: IcebergTableCreation) async throws {
    let catalog = storage.analytics.catalog(bucket: "events")

    _ = try await catalog.createTable(creation, in: "sales")
    _ = try await catalog.listTables(in: "sales")
    _ = try await catalog.table("orders", in: "sales")
    _ = try await catalog.updateTable(
      "orders", in: "sales", requirements: [.assertCreate()], updates: [.setLocation("s3://b/t")])
    _ = try await catalog.tableExists("orders", in: "sales")
    try await catalog.deleteTable("orders", in: "sales", purge: true)
  }
}
