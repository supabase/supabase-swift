//
//  RealtimeIntegrationTests.swift
//
//
//  Created by Guilherme Souza on 27/03/24.
//

import Clocks
import ConcurrencyExtras
import CustomDump
import Helpers
import InlineSnapshotTesting
import PostgREST
import Supabase
import TestHelpers
import XCTest

@testable import Realtime

struct TestLogger: SupabaseLogger {
  func log(message: SupabaseLogMessage) {
    print(message.description)
  }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
final class RealtimeIntegrationTests: XCTestCase {

  let testClock = TestClock<Duration>()

  let client = SupabaseClient(
    supabaseURL: URL(string: DotEnv.SUPABASE_URL)!,
    supabaseKey: DotEnv.SUPABASE_ANON_KEY
  )

  override func setUp() {
    super.setUp()

    _clock = testClock
  }

  override func invokeTest() {
    withMainSerialExecutor {
      super.invokeTest()
    }
  }

  func testDisconnectByUser_shouldNotReconnect() async {
    await client.realtimeV2.connect()
    XCTAssertEqual(client.realtimeV2.status, .connected)

    client.realtimeV2.disconnect()

    /// Wait for the reconnection delay
    await testClock.advance(by: .seconds(RealtimeClientOptions.defaultReconnectDelay))

    XCTAssertEqual(client.realtimeV2.status, .disconnected)
  }

  func testBroadcast() async throws {
    let channel = client.realtimeV2.channel("integration") {
      $0.broadcast.receiveOwnBroadcasts = true
    }

    let receivedMessagesTask = Task {
      await channel.broadcastStream(event: "test").prefix(3).collect()
    }

    await Task.yield()

    await channel.subscribe()

    struct Message: Codable {
      var value: Int
    }

    try await channel.broadcast(event: "test", message: Message(value: 1))
    try await channel.broadcast(event: "test", message: Message(value: 2))
    try await channel.broadcast(event: "test", message: ["value": 3, "another_value": 42])

    let receivedMessages = try await withTimeout(interval: 5) {
      await receivedMessagesTask.value
    }

    assertInlineSnapshot(of: receivedMessages, as: .json) {
      """
      [
        {
          "event" : "test",
          "payload" : {
            "value" : 1
          },
          "type" : "broadcast"
        },
        {
          "event" : "test",
          "payload" : {
            "value" : 2
          },
          "type" : "broadcast"
        },
        {
          "event" : "test",
          "payload" : {
            "another_value" : 42,
            "value" : 3
          },
          "type" : "broadcast"
        }
      ]
      """
    }

    await channel.unsubscribe()
  }

  func testBroadcastWithUnsubscribedChannel() async throws {
    let channel = client.realtimeV2.channel("integration") {
      $0.broadcast.acknowledgeBroadcasts = true
    }

    struct Message: Codable {
      var value: Int
    }

    try await channel.broadcast(event: "test", message: Message(value: 1))
    try await channel.broadcast(event: "test", message: Message(value: 2))
    try await channel.broadcast(event: "test", message: ["value": 3, "another_value": 42])
  }

  func testPresence() async throws {
    let channel = client.realtimeV2.channel("integration") {
      $0.broadcast.receiveOwnBroadcasts = true
    }

    let receivedPresenceChangesTask = Task {
      await channel.presenceChange().prefix(4).collect()
    }

    await Task.yield()

    await channel.subscribe()

    struct UserState: Codable, Equatable {
      let email: String
    }

    try await channel.track(UserState(email: "test@supabase.com"))
    try await channel.track(["email": "test2@supabase.com"])

    await channel.untrack()

    let receivedPresenceChanges = try await withTimeout(interval: 5) {
      await receivedPresenceChangesTask.value
    }

    let joins = try receivedPresenceChanges.map { try $0.decodeJoins(as: UserState.self) }
    let leaves = try receivedPresenceChanges.map { try $0.decodeLeaves(as: UserState.self) }
    expectNoDifference(
      joins,
      [
        [],  // This is the first PRESENCE_STATE event.
        [UserState(email: "test@supabase.com")],
        [UserState(email: "test2@supabase.com")],
        [],
      ]
    )

    expectNoDifference(
      leaves,
      [
        [],  // This is the first PRESENCE_STATE event.
        [],
        [UserState(email: "test@supabase.com")],
        [UserState(email: "test2@supabase.com")],
      ]
    )

    await channel.unsubscribe()
  }

  func testPostgresChanges() async throws {
    let channel = client.realtimeV2.channel("db-changes")

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

    await Task.yield()
    await channel.subscribe()

    struct Entry: Codable, Equatable {
      let key: String
      let value: AnyJSON
    }

    // Wait until a system event for makind sure DB change listeners are set before making DB changes.
    _ = await channel.system().first(where: { _ in true })

    let key = try await
      (client.from("key_value_storage")
      .insert(["key": AnyJSON.string(UUID().uuidString), "value": "value1"]).select().single()
      .execute().value as Entry).key
    try await client.from("key_value_storage").update(["value": "value2"]).eq("key", value: key)
      .execute()
    try await client.from("key_value_storage").delete().eq("key", value: key).execute()

    let insertedEntries = try await receivedInsertActions.value.map {
      try $0.decodeRecord(
        as: Entry.self,
        decoder: JSONDecoder()
      )
    }
    let updatedEntries = try await receivedUpdateActions.value.map {
      try $0.decodeRecord(
        as: Entry.self,
        decoder: JSONDecoder()
      )
    }
    let deletedEntryIds = await receivedDeleteActions.value.compactMap {
      $0.oldRecord["key"]?.stringValue
    }

    expectNoDifference(insertedEntries, [Entry(key: key, value: "value1")])
    expectNoDifference(updatedEntries, [Entry(key: key, value: "value2")])
    expectNoDifference(deletedEntryIds, [key])

    let receivedAnyActions = await receivedAnyActionsTask.value
    XCTAssertEqual(receivedAnyActions.count, 3)

    if case let .insert(action) = receivedAnyActions[0] {
      let record = try action.decodeRecord(as: Entry.self, decoder: JSONDecoder())
      expectNoDifference(record, Entry(key: key, value: "value1"))
    } else {
      XCTFail("Expected a `AnyAction.insert` on `receivedAnyActions[0]`")
    }

    if case let .update(action) = receivedAnyActions[1] {
      let record = try action.decodeRecord(as: Entry.self, decoder: JSONDecoder())
      expectNoDifference(record, Entry(key: key, value: "value2"))
    } else {
      XCTFail("Expected a `AnyAction.update` on `receivedAnyActions[1]`")
    }

    if case let .delete(action) = receivedAnyActions[2] {
      expectNoDifference(key, action.oldRecord["key"]?.stringValue)
    } else {
      XCTFail("Expected a `AnyAction.delete` on `receivedAnyActions[2]`")
    }

    await channel.unsubscribe()
  }
}
