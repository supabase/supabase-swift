//
//  IcebergCommitTests.swift
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
struct IcebergCommitTests {
  @Test
  func updateTablePostsRequirementsAndUpdates() async throws {
    let sent = LockIsolated<[Sent]>([])
    let catalog = try makeCatalog(
      sent: sent,
      response: #"""
        {
          "metadata-location": "file:/tmp/warehouse/t2/metadata/00001.metadata.json",
          "metadata": {
            "format-version": 2,
            "table-uuid": "9999397f-3aa0-4d28-b1d7-4f8e25a86054",
            "properties": {"k": "v"}
          }
        }
        """#)

    let table = try await catalog.updateTable(
      "orders",
      in: "sales",
      requirements: [.assertCurrentSchemaID(0)],
      updates: [.setProperties(["k": "v"])]
    )

    let request = try #require(sent.value.first)
    #expect(request.request.method == .post)
    #expect(request.request.path == "/storage/v1/iceberg/v1/events/namespaces/sales/tables/orders")
    #expect(
      try jsonEqual(
        request.body,
        #"""
        {
          "requirements": [{"type": "assert-current-schema-id", "current-schema-id": 0}],
          "updates": [{"action": "set-properties", "updates": {"k": "v"}}]
        }
        """#))
    #expect(table.metadataLocation == "file:/tmp/warehouse/t2/metadata/00001.metadata.json")
    #expect(table.metadata.tableUUID == "9999397f-3aa0-4d28-b1d7-4f8e25a86054")
    #expect(table.metadata.properties == ["k": "v"])
  }

  @Test
  func aFailedRequirementThrowsCommitFailed() async throws {
    let catalog = try makeCatalog(
      status: .conflict,
      response: #"""
        {"error":{"message":"Requirement failed: UUID does not match","type":"CommitFailedException","code":409}}
        """#)

    let error = try await #require(throws: StorageError.self) {
      try await catalog.updateTable(
        "orders", in: "sales",
        requirements: [.assertTableUUID("00000000-0000-0000-0000-000000000000")],
        updates: [])
    }
    #expect(error.response?.status == .conflict)
    #expect(error.code?.rawValue == "CommitFailedException")
  }

  @Test
  func anEmptyRequirementListIsStillSent() async throws {
    let sent = LockIsolated<[Sent]>([])
    let catalog = try makeCatalog(
      sent: sent, response: #"{"metadata-location":"m","metadata":{"format-version":2}}"#)

    try await catalog.updateTable("orders", in: "sales", updates: [.setLocation("s3://b/t")])

    let body = try #require(sent.value.first?.body)
    #expect(body.contains(#""requirements":[]"#))
  }

  @Test
  func eachFactorySpellsItsWireShape() throws {
    let schema = IcebergSchema(
      schemaID: 1, fields: [IcebergField(id: 1, name: "id", type: .long, isRequired: true)])
    let spec = IcebergPartitionSpec(
      specID: 1, fields: [IcebergPartitionField(sourceID: 1, name: "id", transform: .identity)])
    let order = IcebergSortOrder(
      orderID: 1,
      fields: [
        IcebergSortField(
          sourceID: 1, transform: .identity, direction: .ascending, nullOrder: .nullsFirst)
      ])

    #expect(
      try JSONValue(IcebergTableUpdate.assignUUID("u")) == ["action": "assign-uuid", "uuid": "u"])
    #expect(
      try JSONValue(IcebergTableUpdate.upgradeFormatVersion(to: 3))
        == ["action": "upgrade-format-version", "format-version": 3])
    #expect(
      try JSONValue(IcebergTableUpdate.addSchema(schema))
        == ["action": "add-schema", "schema": try JSONValue(schema)])
    #expect(
      try JSONValue(IcebergTableUpdate.addSchema(schema, lastColumnID: 1))
        == ["action": "add-schema", "schema": try JSONValue(schema), "last-column-id": 1])
    #expect(
      try JSONValue(IcebergTableUpdate.setCurrentSchema(id: -1))
        == ["action": "set-current-schema", "schema-id": -1])
    #expect(
      try JSONValue(IcebergTableUpdate.addPartitionSpec(spec))
        == ["action": "add-spec", "spec": try JSONValue(spec)])
    #expect(
      try JSONValue(IcebergTableUpdate.setDefaultPartitionSpec(id: 1))
        == ["action": "set-default-spec", "spec-id": 1])
    #expect(
      try JSONValue(IcebergTableUpdate.addSortOrder(order))
        == ["action": "add-sort-order", "sort-order": try JSONValue(order)])
    #expect(
      try JSONValue(IcebergTableUpdate.setDefaultSortOrder(id: 1))
        == ["action": "set-default-sort-order", "sort-order-id": 1])
    #expect(
      try JSONValue(IcebergTableUpdate.setLocation("s3://b/t"))
        == ["action": "set-location", "location": "s3://b/t"])
    #expect(
      try JSONValue(IcebergTableUpdate.setProperties(["k": "v"]))
        == ["action": "set-properties", "updates": ["k": "v"]])
    #expect(
      try JSONValue(IcebergTableUpdate.removeProperties(["k"]))
        == ["action": "remove-properties", "removals": ["k"]])

    #expect(try JSONValue(IcebergTableRequirement.assertCreate()) == ["type": "assert-create"])
    #expect(
      try JSONValue(IcebergTableRequirement.assertTableUUID("u"))
        == ["type": "assert-table-uuid", "uuid": "u"])
    #expect(
      try JSONValue(IcebergTableRequirement.assertRefSnapshotID(ref: "main", snapshotID: 7))
        == ["type": "assert-ref-snapshot-id", "ref": "main", "snapshot-id": 7])
    #expect(
      try JSONValue(IcebergTableRequirement.assertCurrentSchemaID(1))
        == ["type": "assert-current-schema-id", "current-schema-id": 1])
    #expect(
      try JSONValue(IcebergTableRequirement.assertLastAssignedFieldID(2))
        == ["type": "assert-last-assigned-field-id", "last-assigned-field-id": 2])
    #expect(
      try JSONValue(IcebergTableRequirement.assertLastAssignedPartitionID(1000))
        == ["type": "assert-last-assigned-partition-id", "last-assigned-partition-id": 1000])
    #expect(
      try JSONValue(IcebergTableRequirement.assertDefaultSpecID(1))
        == ["type": "assert-default-spec-id", "default-spec-id": 1])
    #expect(
      try JSONValue(IcebergTableRequirement.assertDefaultSortOrderID(1))
        == ["type": "assert-default-sort-order-id", "default-sort-order-id": 1])
  }

  @Test
  func aNilSnapshotIDEncodesNull() throws {
    let requirement = IcebergTableRequirement.assertRefSnapshotID(ref: "main", snapshotID: nil)

    let text = String(decoding: try JSONEncoder().encode(requirement), as: UTF8.self)

    #expect(
      try jsonEqual(text, #"{"type":"assert-ref-snapshot-id","ref":"main","snapshot-id":null}"#))
  }

  @Test
  func aLargeSnapshotIDEncodesExactly() throws {
    let requirement = IcebergTableRequirement.assertRefSnapshotID(
      ref: "main", snapshotID: 9_007_199_254_740_993)

    let text = String(decoding: try JSONEncoder().encode(requirement), as: UTF8.self)

    #expect(text.contains(#""snapshot-id":9007199254740993"#))
  }

  @Test
  func customActionsPassThrough() throws {
    let update = IcebergTableUpdate.custom("add-snapshot", fields: ["snapshot": ["snapshot-id": 1]])
    let requirement = IcebergTableRequirement.custom("assert-new", fields: ["x": true])

    #expect(update.action == "add-snapshot")
    #expect(
      try JSONValue(update) == ["action": "add-snapshot", "snapshot": ["snapshot-id": 1]])
    #expect(requirement.kind == "assert-new")
    #expect(try JSONValue(requirement) == ["type": "assert-new", "x": true])
  }

  @Test
  func theDiscriminatorWinsOverAFieldOfTheSameName() throws {
    let update = IcebergTableUpdate.custom("set-location", fields: ["action": "other"])
    let requirement = IcebergTableRequirement.custom("assert-create", fields: ["type": "other"])

    #expect(try JSONValue(update) == ["action": "set-location"])
    #expect(try JSONValue(requirement) == ["type": "assert-create"])
  }
}
