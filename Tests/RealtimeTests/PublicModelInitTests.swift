//
//  PublicModelInitTests.swift
//  Realtime
//

import Foundation
import Testing

// A plain `import Realtime`, not `@testable`: the tests see only the public API, the way an app
// building fixtures and previews does.
import Realtime

@Suite struct RealtimePublicModelInitTests {
  @Test func postgresModelsAreBuildable() {
    let column = PostgresColumn(name: "id", type: "int8")
    let row = PostgresRow(values: ["id": 1])
    var change = PostgresChange(
      kind: .insert, schema: "public", table: "todos",
      commitTimestamp: Date(timeIntervalSince1970: 1_700_000_000), columns: [column], record: row)
    change.errors = ["Error 401: Unauthorized"]

    #expect(change.record?["id"] == 1)
    #expect(change.oldRecord == nil)
    #expect(change.errors.count == 1)
  }

  @Test func broadcastMessageIsBuildableAndDecodes() throws {
    struct Cursor: Decodable, Equatable { var x: Int }

    var message = BroadcastMessage(event: "cursor", payload: .json(["x": 1]))
    #expect(!message.isReplayed)
    #expect(message.id == nil)
    #expect(try message.decode(as: Cursor.self) == Cursor(x: 1))

    message.isReplayed = true
    #expect(message.isReplayed)
  }
}
