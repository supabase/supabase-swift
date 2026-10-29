//
//  PostgresChangeTests.swift
//  Realtime
//
//  Created by Guilherme Souza on 29/10/26.
//

import Foundation
import InlineSnapshotTesting
import SnapshotTestingCustomDump
import Testing

@testable import Realtime

@Suite
struct PostgresChangeTests {
  struct Todo: Decodable, Equatable {
    let id: Int
    let title: String
  }

  private let columns: JSONValue = [
    ["name": "id", "type": "int8"], ["name": "title", "type": "text"],
  ]

  private func data(
    _ type: String, record: JSONValue? = nil, oldRecord: JSONValue? = nil,
    errors: JSONValue = .null, commitTimestamp: String = "2026-10-08T10:00:00.000Z"
  ) -> JSONObject {
    var data: JSONObject = [
      "type": .string(type), "schema": "public", "table": "todos",
      "commit_timestamp": .string(commitTimestamp), "columns": columns, "errors": errors,
    ]
    data["record"] = record
    data["old_record"] = oldRecord
    return data
  }

  @Test
  func insert() throws {
    let change = try PostgresChange(payload: data("INSERT", record: ["id": 1, "title": "a"]))
    assertInlineSnapshot(of: change, as: .customDump) {
      """
      PostgresChange(
        kind: PostgresChange.Kind(rawValue: "INSERT"),
        schema: "public",
        table: "todos",
        commitTimestamp: Date(2026-10-08T10:00:00.000Z),
        columns: [
          [0]: PostgresColumn(
            name: "id",
            type: "int8"
          ),
          [1]: PostgresColumn(
            name: "title",
            type: "text"
          )
        ],
        record: PostgresRow(
          values: [
            "id": .integer(1),
            "title": .string("a")
          ]
        ),
        oldRecord: nil,
        errors: []
      )
      """
    }
  }

  @Test
  func update() throws {
    let change = try PostgresChange(
      payload: data("UPDATE", record: ["id": 1, "title": "b"], oldRecord: ["id": 1, "title": "a"]))
    assertInlineSnapshot(of: change, as: .customDump) {
      """
      PostgresChange(
        kind: PostgresChange.Kind(rawValue: "UPDATE"),
        schema: "public",
        table: "todos",
        commitTimestamp: Date(2026-10-08T10:00:00.000Z),
        columns: [
          [0]: PostgresColumn(
            name: "id",
            type: "int8"
          ),
          [1]: PostgresColumn(
            name: "title",
            type: "text"
          )
        ],
        record: PostgresRow(
          values: [
            "id": .integer(1),
            "title": .string("b")
          ]
        ),
        oldRecord: PostgresRow(
          values: [
            "id": .integer(1),
            "title": .string("a")
          ]
        ),
        errors: []
      )
      """
    }
  }

  @Test
  func deleteWithAPrimaryKeyOnlyOldRecord() throws {
    let change = try PostgresChange(payload: data("DELETE", oldRecord: ["id": 1]))
    assertInlineSnapshot(of: change, as: .customDump) {
      """
      PostgresChange(
        kind: PostgresChange.Kind(rawValue: "DELETE"),
        schema: "public",
        table: "todos",
        commitTimestamp: Date(2026-10-08T10:00:00.000Z),
        columns: [
          [0]: PostgresColumn(
            name: "id",
            type: "int8"
          ),
          [1]: PostgresColumn(
            name: "title",
            type: "text"
          )
        ],
        record: nil,
        oldRecord: PostgresRow(
          values: [
            "id": .integer(1)
          ]
        ),
        errors: []
      )
      """
    }
    #expect(change.oldRecord?["id"] == 1)
  }

  @Test(arguments: [
    "Error 401: Unauthorized", "Error 400: Bad Request", "Error 413: Payload Too Large",
  ])
  func errors(message: String) throws {
    let change = try PostgresChange(
      payload: data("INSERT", record: ["id": 1], errors: [.string(message)]))
    #expect(change.errors == [message])
  }

  @Test
  func commitTimestampWithAnOffsetDecodesToTheRightInstant() throws {
    let change = try PostgresChange(
      payload: data(
        "INSERT", record: ["id": 1], commitTimestamp: "2026-10-08T12:00:00.000+02:00"))
    #expect(change.commitTimestamp == Date(timeIntervalSince1970: 1_791_453_600))
  }

  @Test
  func unknownTypeIsKeptAsItsRawValue() throws {
    let change = try PostgresChange(payload: data("TRUNCATE"))
    #expect(change.kind == PostgresChange.Kind(rawValue: "TRUNCATE"))
    #expect(change.record == nil)
    #expect(change.oldRecord == nil)
  }

  @Test
  func missingTableThrowsADecodingError() {
    var payload = data("INSERT", record: ["id": 1])
    payload["table"] = nil
    let error = #expect(throws: RealtimeError.self) { try PostgresChange(payload: payload) }
    #expect(error?.kind == .decoding)
  }

  @Test
  func invalidCommitTimestampThrowsADecodingError() {
    let error = #expect(throws: RealtimeError.self) {
      try PostgresChange(payload: data("INSERT", record: ["id": 1], commitTimestamp: "yesterday"))
    }
    #expect(error?.kind == .decoding)
  }

  @Test
  func rowDecodesWithTheDefaultDecoder() throws {
    let change = try PostgresChange(payload: data("INSERT", record: ["id": 1, "title": "a"]))
    #expect(try change.record?.decode(as: Todo.self) == Todo(id: 1, title: "a"))
  }

  @Test
  func rowDecodeFailureThrowsADecodingError() throws {
    let change = try PostgresChange(payload: data("INSERT", record: ["id": "x"]))
    let record = try #require(change.record)
    let error = #expect(throws: RealtimeError.self) { try record.decode(as: Todo.self) }
    #expect(error?.kind == .decoding)
    #expect(error?.underlyingError is DecodingError)
  }

  // MARK: - TypedPostgresChange

  private func typed(_ change: PostgresChange) -> TypedPostgresChange<Todo> {
    TypedPostgresChange(raw: change, decoder: .supabase())
  }

  @Test
  func typedRowDecodesAnInsert() throws {
    let change = typed(
      try PostgresChange(payload: data("INSERT", record: ["id": 1, "title": "a"])))
    #expect(change.kind == .insert)
    #expect(try change.row() == Todo(id: 1, title: "a"))
  }

  @Test
  func typedRowThrowsOnADelete() throws {
    let change = typed(try PostgresChange(payload: data("DELETE", oldRecord: ["id": 1])))
    let error = #expect(throws: RealtimeError.self) { try change.row() }
    #expect(error?.kind == .decoding)
    #expect(change.oldRecord?["id"] == 1)
  }

  @Test
  func typedRowThrowsOnAMalformedRecordAndKeepsTheRawChange() throws {
    let change = typed(try PostgresChange(payload: data("INSERT", record: ["id": "x"])))
    let error = #expect(throws: RealtimeError.self) { try change.row() }
    #expect(error?.kind == .decoding)
    #expect(error?.underlyingError is DecodingError)
    #expect(change.raw.record?["id"] == "x")
  }
}
