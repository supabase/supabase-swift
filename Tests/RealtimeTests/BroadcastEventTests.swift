import InlineSnapshotTesting
import SnapshotTestingCustomDump
import XCTest

@testable import Realtime

final class BroadcastEventTests: XCTestCase {
  func testBroadcastChangeDecoding() throws {
    // Test INSERT operation
    let insertJSON = Data(
      """
      {
          "schema": "public",
          "table": "users",
          "operation": "INSERT",
          "record": {
              "id": 1,
              "name": "John Doe",
              "email": "john@example.com"
          },
          "old_record": null
      }
      """.utf8
    )

    let insertChange = try JSONDecoder().decode(BroadcastChange.self, from: insertJSON)

    assertInlineSnapshot(of: insertChange, as: .customDump) {
      """
      BroadcastChange(
        schema: "public",
        table: "users",
        operation: .insert(
          new: [
            "email": .string("john@example.com"),
            "id": .integer(1),
            "name": .string("John Doe")
          ]
        )
      )
      """
    }

    // Test UPDATE operation
    let updateJSON = Data(
      """
      {
          "schema": "public",
          "table": "users",
          "operation": "UPDATE",
          "record": {
              "id": 1,
              "name": "John Updated",
              "email": "john@example.com"
          },
          "old_record": {
              "id": 1,
              "name": "John Doe",
              "email": "john@example.com"
          }
      }
      """.utf8
    )

    let updateChange = try JSONDecoder().decode(BroadcastChange.self, from: updateJSON)
    assertInlineSnapshot(of: updateChange, as: .customDump) {
      """
      BroadcastChange(
        schema: "public",
        table: "users",
        operation: .update(
          new: [
            "email": .string("john@example.com"),
            "id": .integer(1),
            "name": .string("John Updated")
          ],
          old: [
            "email": .string("john@example.com"),
            "id": .integer(1),
            "name": .string("John Doe")
          ]
        )
      )
      """
    }

    // Test DELETE operation
    let deleteJSON = Data(
      """
      {
          "schema": "public",
          "table": "users",
          "operation": "DELETE",
          "record": null,
          "old_record": {
              "id": 1,
              "name": "John Doe",
              "email": "john@example.com"
          }
      }
      """.utf8
    )

    let deleteChange = try JSONDecoder().decode(BroadcastChange.self, from: deleteJSON)

    assertInlineSnapshot(of: deleteChange, as: .customDump) {
      """
      BroadcastChange(
        schema: "public",
        table: "users",
        operation: .delete(
          old: [
            "email": .string("john@example.com"),
            "id": .integer(1),
            "name": .string("John Doe")
          ]
        )
      )
      """
    }
  }

  func testBroadcastChangeEncoding() throws {
    // Test INSERT operation encoding
    let insertChange = BroadcastChange(
      schema: "public",
      table: "users",
      operation: .insert(new: [
        "id": 1,
        "name": "John Doe",
        "email": "john@example.com",
      ])
    )

    let insertJSON = try JSONObject(insertChange)
    assertInlineSnapshot(of: insertJSON, as: .json) {
      """
      {
        "old_record" : null,
        "operation" : "INSERT",
        "record" : {
          "email" : "john@example.com",
          "id" : 1,
          "name" : "John Doe"
        },
        "schema" : "public",
        "table" : "users"
      }
      """
    }

    // Test UPDATE operation encoding
    let updateChange = BroadcastChange(
      schema: "public",
      table: "users",
      operation: .update(
        new: ["id": 1, "name": "John Updated"],
        old: ["id": 1, "name": "John Doe"]
      )
    )

    let updateJSON = try JSONObject(updateChange)
    assertInlineSnapshot(of: updateJSON, as: .json) {
      """
      {
        "old_record" : {
          "id" : 1,
          "name" : "John Doe"
        },
        "operation" : "UPDATE",
        "record" : {
          "id" : 1,
          "name" : "John Updated"
        },
        "schema" : "public",
        "table" : "users"
      }
      """
    }

    // Test DELETE operation encoding
    let deleteChange = BroadcastChange(
      schema: "public",
      table: "users",
      operation: .delete(old: [
        "id": 1,
        "name": "John Doe",
      ])
    )

    let deleteJSON = try JSONObject(deleteChange)
    assertInlineSnapshot(of: deleteJSON, as: .json) {
      """
      {
        "old_record" : {
          "id" : 1,
          "name" : "John Doe"
        },
        "operation" : "DELETE",
        "record" : null,
        "schema" : "public",
        "table" : "users"
      }
      """
    }
  }

  func testBroadcastEvent() throws {
    let eventJSON = Data(
      """
      {
          "type": "broadcast",
          "event": "test_event",
          "payload": {
              "schema": "public",
              "table": "users",
              "operation": "INSERT",
              "record": {
                  "id": 1,
                  "name": "John Doe"
              },
              "old_record": null
          }
      }
      """.utf8
    )

    let event = try JSONDecoder().decode(BroadcastEvent.self, from: eventJSON)

    XCTAssertEqual(event.type, "broadcast")
    XCTAssertEqual(event.event, "test_event")

    let change = try event.broadcastChange()
    XCTAssertEqual(change.schema, "public")
    XCTAssertEqual(change.table, "users")

    if case .insert(let new) = change.operation {
      XCTAssertEqual(new["id"]?.intValue, 1)
      XCTAssertEqual(new["name"]?.stringValue, "John Doe")
    } else {
      XCTFail("Expected INSERT operation")
    }
  }
}
