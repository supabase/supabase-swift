//
//  RealtimeIntegrationTests.swift
//
//
//  Created by Guilherme Souza on 27/03/24.
//

import ConcurrencyExtras
import CustomDump
import PostgREST
@testable import Realtime
import XCTest

final class RealtimeIntegrationTests: XCTestCase {
  let realtime = RealtimeClientV2(
    config: RealtimeClientV2.Configuration(
      url: URL(string: "http://localhost:54321/realtime/v1")!,
      apiKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"
    )
  )

  let db = PostgrestClient(
    url: URL(string: "http://localhost:54321/rest/v1")!,
    headers: [
      "apikey": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU",
    ],
    logger: nil
  )

  func testBroadcast() async throws {
    let expectation = expectation(description: "receivedBroadcastMessages")
    expectation.expectedFulfillmentCount = 3

    let channel = await realtime.channel("integration") {
      $0.broadcast.receiveOwnBroadcasts = true
    }

    let receivedMessages = LockIsolated<[JSONObject]>([])

    Task {
      for await message in await channel.broadcast(event: "test") {
        receivedMessages.withValue {
          $0.append(message)
        }
        expectation.fulfill()
      }
    }

    await Task.megaYield()

    await channel.subscribe()

    struct Message: Codable {
      var value: Int
    }

    try await channel.broadcast(event: "test", message: Message(value: 1))
    try await channel.broadcast(event: "test", message: Message(value: 2))
    try await channel.broadcast(event: "test", message: ["value": 3, "another_value": 42])

    await fulfillment(of: [expectation], timeout: 0.5)

    XCTAssertNoDifference(
      receivedMessages.value,
      [
        [
          "event": "test",
          "payload": [
            "value": 1,
          ],
          "type": "broadcast",
        ],
        [
          "event": "test",
          "payload": [
            "value": 2,
          ],
          "type": "broadcast",
        ],
        [
          "event": "test",
          "payload": [
            "value": 3,
            "another_value": 42,
          ],
          "type": "broadcast",
        ],
      ]
    )

    await channel.unsubscribe()
  }

  func testPresence() async throws {
    let channel = await realtime.channel("integration") {
      $0.broadcast.receiveOwnBroadcasts = true
    }

    let expectation = expectation(description: "presenceChange")
    expectation.expectedFulfillmentCount = 4

    let receivedPresenceChanges = LockIsolated<[any PresenceAction]>([])

    Task {
      for await presence in await channel.presenceChange() {
        receivedPresenceChanges.withValue {
          $0.append(presence)
        }
        expectation.fulfill()
      }
    }

    await Task.megaYield()

    await channel.subscribe()

    struct UserState: Codable, Equatable {
      let email: String
    }

    try await channel.track(UserState(email: "test@supabase.com"))
    try await channel.track(["email": "test2@supabase.com"])

    await channel.untrack()

    await fulfillment(of: [expectation], timeout: 0.5)

    let joins = try receivedPresenceChanges.value.map { try $0.decodeJoins(as: UserState.self) }
    let leaves = try receivedPresenceChanges.value.map { try $0.decodeLeaves(as: UserState.self) }
    XCTAssertNoDifference(
      joins,
      [
        [], // This is the first PRESENCE_STATE event.
        [UserState(email: "test@supabase.com")],
        [UserState(email: "test2@supabase.com")],
        [],
      ]
    )

    XCTAssertNoDifference(
      leaves,
      [
        [], // This is the first PRESENCE_STATE event.
        [],
        [UserState(email: "test@supabase.com")],
        [UserState(email: "test2@supabase.com")],
      ]
    )

    await channel.unsubscribe()
  }

  func testPostgresChanges() async throws {
    let channel = await realtime.channel("db-changes")

    let receivedInsertActions = Task {
      await channel.postgresChange(InsertAction.self, schema: "public").prefix(1).collect()
    }

    let receivedUpdateActions = Task {
      await channel.postgresChange(UpdateAction.self, schema: "public").prefix(1).collect()
    }

    let receivedDeleteActions = Task {
      await channel.postgresChange(DeleteAction.self, schema: "public").prefix(1).collect()
    }

    let receivedAnyActionsTask = Task {
      await channel.postgresChange(AnyAction.self, schema: "public").prefix(3).collect()
    }

    await Task.megaYield()
    await channel.subscribe()

    struct Entry: Codable, Equatable {
      let key: String
      let value: AnyJSON
    }

    let key = try await (
      db.from("store")
        .insert(["key": AnyJSON.string(UUID().uuidString), "value": "value1"]).select().single()
        .execute().value as Entry
    ).key
    try await db.from("store").update(["value": "value2"]).eq("key", value: key).execute()
    try await db.from("store").delete().eq("key", value: key).execute()

    let insertedEntries = try await receivedInsertActions.value.map { try $0.decodeRecord(
      as: Entry.self,
      decoder: JSONDecoder()
    ) }
    let updatedEntries = try await receivedUpdateActions.value.map { try $0.decodeRecord(
      as: Entry.self,
      decoder: JSONDecoder()
    ) }
    let deletedEntryIds = await receivedDeleteActions.value
      .compactMap { $0.oldRecord["key"]?.stringValue }

    XCTAssertNoDifference(insertedEntries, [Entry(key: key, value: "value1")])
    XCTAssertNoDifference(updatedEntries, [Entry(key: key, value: "value2")])
    XCTAssertNoDifference(deletedEntryIds, [key])

    let receivedAnyActions = await receivedAnyActionsTask.value
    XCTAssertEqual(receivedAnyActions.count, 3)

    if case let .insert(action) = receivedAnyActions[0] {
      let record = try action.decodeRecord(as: Entry.self, decoder: JSONDecoder())
      XCTAssertNoDifference(record, Entry(key: key, value: "value1"))
    } else {
      XCTFail("Expected a `AnyAction.insert` on `receivedAnyActions[0]`")
    }

    if case let .update(action) = receivedAnyActions[1] {
      let record = try action.decodeRecord(as: Entry.self, decoder: JSONDecoder())
      XCTAssertNoDifference(record, Entry(key: key, value: "value2"))
    } else {
      XCTFail("Expected a `AnyAction.update` on `receivedAnyActions[1]`")
    }

    if case let .delete(action) = receivedAnyActions[2] {
      XCTAssertNoDifference(key, action.oldRecord["key"]?.stringValue)
    } else {
      XCTFail("Expected a `AnyAction.delete` on `receivedAnyActions[2]`")
    }

    await channel.unsubscribe()
  }
}
