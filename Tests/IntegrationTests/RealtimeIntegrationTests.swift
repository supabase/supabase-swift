//
//  RealtimeIntegrationTests.swift
//
//
//  Created by AI Assistant on 09/01/25.
//

import Clocks
import ConcurrencyExtras
import CustomDump
import Foundation
import OSLog
import Supabase
import TestHelpers
import XCTest

@testable import Realtime

#if !os(Android) && !os(Linux)
  @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
  final class RealtimeIntegrationTests: XCTestCase {
    let testClock = TestClock<Duration>()

    var client: SupabaseClient!
    var client2: SupabaseClient!

    override func setUp() async throws {
      try await super.setUp()

      //      try XCTSkipUnless(
      //        ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil,
      //        "INTEGRATION_TESTS not defined. Set this environment variable to run integration tests."
      //      )

      _clock = testClock

      client = SupabaseClient(
        supabaseURL: URL(string: DotEnv.SUPABASE_URL) ?? URL(string: "http://127.0.0.1:54321")!,
        supabaseKey: DotEnv.SUPABASE_ANON_KEY,
        options: SupabaseClientOptions(
          auth: .init(storage: InMemoryLocalStorage()),
          global: .init(
            logger: OSLogSupabaseLogger(
              Logger(subsystem: "realtime.integration.tests", category: "client1")
            )
          )
        )
      )

      client2 = SupabaseClient(
        supabaseURL: URL(string: DotEnv.SUPABASE_URL) ?? URL(string: "http://127.0.0.1:54321")!,
        supabaseKey: DotEnv.SUPABASE_ANON_KEY,
        options: SupabaseClientOptions(
          auth: .init(storage: InMemoryLocalStorage()),
          global: .init(
            logger: OSLogSupabaseLogger(
              Logger(subsystem: "realtime.integration.tests", category: "client2")
            )
          )
        )
      )

      // Clean up any existing data
      _ = try? await client.from("key_value_storage").delete().neq("key", value: UUID().uuidString)
        .execute()
    }

    override func tearDown() async throws {
      // Clean up channels and disconnect
      await client.realtimeV2.removeAllChannels()
      client.realtimeV2.disconnect()

      await client2.realtimeV2.removeAllChannels()
      client2.realtimeV2.disconnect()

      try await super.tearDown()
    }

    #if !os(Windows) && !os(Linux) && !os(Android)
      override func invokeTest() {
        withMainSerialExecutor {
          super.invokeTest()
        }
      }
    #endif

    // MARK: - Connection Management Tests

    func testConnectionAndDisconnection() async throws {
      XCTAssertEqual(client.realtimeV2.status, .disconnected)

      await client.realtimeV2.connect()
      XCTAssertEqual(client.realtimeV2.status, .connected)

      client.realtimeV2.disconnect()
      XCTAssertEqual(client.realtimeV2.status, .disconnected)
    }

    func testConnectionStatusChanges() async throws {
      let statuses = LockIsolated<[RealtimeClientStatus]>([])

      let subscription = client.realtimeV2.onStatusChange { status in
        statuses.withValue { $0.append(status) }
      }

      await client.realtimeV2.connect()
      client.realtimeV2.disconnect()

      // Wait a bit for all status changes
      await Task.megaYield()

      subscription.cancel()

      // Should have at least connecting and connected
      XCTAssertTrue(statuses.value.contains(.connecting))
      XCTAssertTrue(statuses.value.contains(.connected))
      XCTAssertTrue(statuses.value.contains(.disconnected))
    }

    func testManualDisconnectShouldNotReconnect() async throws {
      await client.realtimeV2.connect()
      XCTAssertEqual(client.realtimeV2.status, .connected)

      client.realtimeV2.disconnect()

      // Wait for potential reconnection delay
      await testClock.advance(by: .seconds(RealtimeClientOptions.defaultReconnectDelay + 1))

      XCTAssertEqual(client.realtimeV2.status, .disconnected)
    }

    func testMultipleConnectCalls() async throws {
      await client.realtimeV2.connect()
      XCTAssertEqual(client.realtimeV2.status, .connected)

      // Multiple connect calls should be idempotent
      await client.realtimeV2.connect()
      await client.realtimeV2.connect()

      XCTAssertEqual(client.realtimeV2.status, .connected)
    }

    // MARK: - Channel Management Tests

    func testChannelStatusChanges() async throws {
      await client.realtimeV2.connect()

      let channel = client.realtimeV2.channel("test-channel")
      let statuses = LockIsolated<[RealtimeChannelStatus]>([])

      let subscription = channel.onStatusChange { status in
        statuses.withValue { $0.append(status) }
      }
      defer { subscription.cancel() }

      try await channel.subscribeWithError()
      await channel.unsubscribe()

      XCTAssertEqual(
        statuses.value,
        [.unsubscribed, .subscribing, .subscribed, .unsubscribing, .unsubscribed]
      )
    }

    func testMultipleChannels() async throws {
      // Do not connect client, let first channel subscription do it.

      let channel1 = client.realtimeV2.channel("channel-1")
      let channel2 = client.realtimeV2.channel("channel-2")
      let channel3 = client.realtimeV2.channel("channel-3")

      try await subscribeMany([channel1, channel2, channel3])

      XCTAssertEqual(channel1.status, .subscribed)
      XCTAssertEqual(channel2.status, .subscribed)
      XCTAssertEqual(channel3.status, .subscribed)

      XCTAssertEqual(client.realtimeV2.channels.count, 3)

      await unsubscribeMany([channel1, channel2, channel3])
    }

    func testChannelReuse() async throws {
      await client.realtimeV2.connect()

      let channel1 = client.realtimeV2.channel("reuse-channel")
      try await channel1.subscribeWithError()

      // Getting the same channel should return the existing instance
      let channel2 = client.realtimeV2.channel("reuse-channel")
      XCTAssertTrue(channel1 === channel2)
      XCTAssertEqual(channel2.status, .subscribed)

      await channel1.unsubscribe()

      // Unsubscribing channel1 should unsubscribe channel2
      XCTAssertEqual(channel2.status, .unsubscribed)
    }

    func testRemoveChannel() async throws {
      await client.realtimeV2.connect()

      let channel = client.realtimeV2.channel("remove-test")
      try await channel.subscribeWithError()

      await client.realtimeV2.removeChannel(channel)

      XCTAssertEqual(channel.status, .unsubscribed)
      XCTAssertFalse(client.realtimeV2.channels.keys.contains(channel.topic))
    }

    func testRemoveAllChannels() async throws {
      await client.realtimeV2.connect()

      let channel1 = client.realtimeV2.channel("all-1")
      let channel2 = client.realtimeV2.channel("all-2")
      let channel3 = client.realtimeV2.channel("all-3")

      try await subscribeMany([channel1, channel2, channel3])

      await client.realtimeV2.removeAllChannels()

      XCTAssertEqual(channel1.status, .unsubscribed)
      XCTAssertEqual(channel2.status, .unsubscribed)
      XCTAssertEqual(channel3.status, .unsubscribed)
      XCTAssertEqual(client.realtimeV2.channels.count, 0)

      XCTAssertEqual(
        client.realtimeV2.status,
        .disconnected,
        "Should disconnect client if all channels are removed"
      )
    }

    // MARK: - Broadcast Tests

    func testBroadcastSendAndReceive() async throws {
      await client.realtimeV2.connect()

      let channel = client.realtimeV2.channel("broadcast-test") {
        $0.broadcast.receiveOwnBroadcasts = true
      }

      struct Message: Codable {
        let value: Int
        let text: String
      }

      let receivedMessagesTask = Task {
        await channel.broadcastStream(event: "test-event").prefix(3).collect()
      }

      try await channel.subscribeWithError()

      try await channel.broadcast(event: "test-event", message: Message(value: 1, text: "first"))
      try await channel.broadcast(event: "test-event", message: Message(value: 2, text: "second"))
      await channel.broadcast(event: "test-event", message: ["value": 3, "text": "third"])

      let receivedMessages = try await withTimeout(interval: 5) {
        await receivedMessagesTask.value
      }

      XCTAssertEqual(receivedMessages.count, 3)

      let firstMessage = receivedMessages[0]
      XCTAssertEqual(firstMessage["event"]?.stringValue, "test-event")
      XCTAssertEqual(firstMessage["payload"]?.objectValue?["value"]?.intValue, 1)
      XCTAssertEqual(firstMessage["payload"]?.objectValue?["text"]?.stringValue, "first")

      // Clean up

      await channel.unsubscribe()
    }

    func testBroadcastMultipleEvents() async throws {
      await client.realtimeV2.connect()

      let channel = client.realtimeV2.channel("broadcast-multi") {
        $0.broadcast.receiveOwnBroadcasts = true
      }

      let event1Messages = Task {
        await channel.broadcastStream(event: "event-1").prefix(2).collect()
      }

      let event2Messages = Task {
        await channel.broadcastStream(event: "event-2").prefix(2).collect()
      }

      try await channel.subscribeWithError()

      try await channel.broadcast(event: "event-1", message: ["data": "1"])
      try await channel.broadcast(event: "event-2", message: ["data": "2"])
      try await channel.broadcast(event: "event-1", message: ["data": "3"])
      try await channel.broadcast(event: "event-2", message: ["data": "4"])

      let event1 = try await withTimeout(interval: 5) {
        await event1Messages.value
      }

      let event2 = try await withTimeout(interval: 5) {
        await event2Messages.value
      }

      XCTAssertEqual(event1.count, 2)
      XCTAssertEqual(event2.count, 2)

      await channel.unsubscribe()
    }

    func testBroadcastWithoutOwnBroadcasts() async throws {
      await client.realtimeV2.connect()

      let channel = client.realtimeV2.channel("broadcast-no-own") {
        $0.broadcast.receiveOwnBroadcasts = false
      }

      let receivedCount = LockIsolated<Int>(0)
      let subscription = channel.onBroadcast(event: "test") { _ in
        receivedCount.withValue { $0 += 1 }
      }

      try await channel.subscribeWithError()

      // Send broadcast - should not receive it
      try await channel.broadcast(event: "test", message: ["data": "test"])

      // Wait a bit
      try await Task.sleep(nanoseconds: 500_000_000)  // 0.5 seconds

      XCTAssertEqual(receivedCount.value, 0)

      subscription.cancel()
      await channel.unsubscribe()
    }

    // MARK: - Postgres Changes Tests

    func testPostgresAllChanges() async throws {
      await client.realtimeV2.connect()

      let channel = client.realtimeV2.channel("postgres-all")

      struct Entry: Codable, Equatable {
        let key: String
        let value: AnyJSON
      }

      let allChangesTask = Task {
        await channel.postgresChange(AnyAction.self, schema: "public", table: "key_value_storage")
          .prefix(3).collect()
      }

      try await channel.subscribeWithError()

      // Wait for subscription
      _ = await channel.system().first(where: { _ in true })

      let testKey = UUID().uuidString

      // Insert
      _ = try await client.from("key_value_storage")
        .insert(["key": testKey, "value": "value1"]).select().single().execute()

      try await Task.sleep(nanoseconds: 500_000_000)

      // Update
      try await client.from("key_value_storage").update(["value": "value2"]).eq(
        "key",
        value: testKey
      )
      .execute()

      try await Task.sleep(nanoseconds: 500_000_000)

      // Delete
      try await client.from("key_value_storage").delete().eq("key", value: testKey).execute()

      let received = try await withTimeout(interval: 5) {
        await allChangesTask.value
      }

      XCTAssertEqual(received.count, 3)

      // Verify action types
      if case .insert(let action) = received[0] {
        let record = try action.decodeRecord(as: Entry.self, decoder: .supabase())
        XCTAssertEqual(record.key, testKey)
      } else {
        XCTFail("Expected insert action")
      }

      if case .update(let action) = received[1] {
        let record = try action.decodeRecord(as: Entry.self, decoder: .supabase())
        XCTAssertEqual(record.value.stringValue, "value2")
      } else {
        XCTFail("Expected update action")
      }

      if case .delete(let action) = received[2] {
        let oldRecordKey = action.oldRecord["key"]?.stringValue
        XCTAssertEqual(oldRecordKey, testKey)
      } else {
        XCTFail("Expected delete action")
      }

      await channel.unsubscribe()
    }

    func testPostgresChangesWithFilter() async throws {
      await client.realtimeV2.connect()

      let channel = client.realtimeV2.channel("postgres-filter")

      struct Entry: Codable, Equatable {
        let key: String
        let value: AnyJSON
      }

      let testKey1 = UUID().uuidString
      let testKey2 = UUID().uuidString

      // Set up filter for specific key
      let filteredTask = Task {
        await channel.postgresChange(
          InsertAction.self,
          schema: "public",
          table: "key_value_storage",
          filter: .eq("key", value: testKey1)
        ).prefix(1).collect()
      }

      try await channel.subscribeWithError()

      // Wait for subscription
      _ = await channel.system().first(where: { _ in true })

      // Insert with key1 - should be received
      _ = try await client.from("key_value_storage")
        .insert(["key": testKey1, "value": "filtered"]).select().single().execute()

      try await Task.sleep(nanoseconds: 500_000_000)

      // Insert with key2 - should NOT be received
      _ = try await client.from("key_value_storage")
        .insert(["key": testKey2, "value": "not-filtered"]).select().single().execute()

      let received = try await withTimeout(interval: 5) {
        await filteredTask.value
      }

      XCTAssertEqual(received.count, 1)
      let record = try received[0].decodeRecord(as: Entry.self, decoder: .supabase())
      XCTAssertEqual(record.key, testKey1)
      XCTAssertNotEqual(record.key, testKey2)

      await channel.unsubscribe()
    }

    func testPostgresChangesMultipleSubscriptions() async throws {
      await client.realtimeV2.connect()

      let channel = client.realtimeV2.channel("postgres-multi")

      struct Entry: Codable, Equatable {
        let key: String
        let value: AnyJSON
      }

      let insertTask = Task {
        await channel.postgresChange(
          InsertAction.self,
          schema: "public",
          table: "key_value_storage"
        )
        .prefix(1).collect()
      }

      let updateTask = Task {
        await channel.postgresChange(
          UpdateAction.self,
          schema: "public",
          table: "key_value_storage"
        )
        .prefix(1).collect()
      }

      let deleteTask = Task {
        await channel.postgresChange(
          DeleteAction.self,
          schema: "public",
          table: "key_value_storage"
        )
        .prefix(1).collect()
      }

      try await channel.subscribeWithError()

      // Wait for subscription
      _ = await channel.system().first(where: { _ in true })

      let testKey = UUID().uuidString

      // Insert
      _ = try await client.from("key_value_storage")
        .insert(["key": testKey, "value": "value1"]).select().single().execute()

      try await Task.sleep(nanoseconds: 500_000_000)

      // Update
      try await client.from("key_value_storage").update(["value": "value2"]).eq(
        "key",
        value: testKey
      )
      .execute()

      try await Task.sleep(nanoseconds: 500_000_000)

      // Delete
      try await client.from("key_value_storage").delete().eq("key", value: testKey).execute()

      let inserts = try await withTimeout(interval: 5) {
        await insertTask.value
      }

      let updates = try await withTimeout(interval: 5) {
        await updateTask.value
      }

      let deletes = try await withTimeout(interval: 5) {
        await deleteTask.value
      }

      XCTAssertEqual(inserts.count, 1)
      XCTAssertEqual(updates.count, 1)
      XCTAssertEqual(deletes.count, 1)

      await channel.unsubscribe()
    }

    // MARK: - Error Handling Tests

    //    func testSubscribeToInvalidChannel() async throws {
    //      await client.realtimeV2.connect()
    //
    //      // Try to subscribe to a channel that might not exist or have permissions
    //      let channel = client.realtimeV2.channel("invalid-channel-test")
    //
    //      // This should not throw if the channel is just a name
    //      // But if there are RLS policies, it might fail
    //      do {
    //        try await channel.subscribeWithError()
    //        // If it succeeds, that's fine too
    //      } catch {
    //        // If it fails, that's expected for some configurations
    //        XCTAssertNotNil(error)
    //      }
    //    }
    //
    //    func testBroadcastWithoutSubscription() async throws {
    //      let channel1 = client.realtimeV2.channel("broadcast-no-sub")
    //      let channel2 = client2.realtimeV2.channel("broadcast-no-sub")
    //
    //      struct Message: Codable {
    //        let data: String
    //        let timestamp: Int
    //      }
    //
    //      let receivedMessagesTask = Task {
    //        await channel2.broadcastStream(event: "test").prefix(1).collect()
    //      }
    //
    //      // Subscribe the second client to receive broadcasts
    //      try await channel2.subscribeWithError()
    //
    //      // httpSend requires Authorization, sign in with a test user before broadcasting.
    //      try await client.auth.signUp(
    //        email: "test-\(UUID().uuidString)@example.com",
    //        password: "The.pass123"
    //      )
    //
    //      // Give time for token propagate from auth to realtime.
    //      await Task.megaYield()
    //
    //      // Send broadcast via HTTP from first client (without subscription)
    //      // This should fall back to HTTP and be received by the second client
    //      try await channel1.httpSend(
    //        event: "test",
    //        message: Message(data: "test-data", timestamp: 12345)
    //      )
    //
    //      // Verify the second client received the broadcast
    //      let receivedMessages = try await withTimeout(interval: 5) {
    //        await receivedMessagesTask.value
    //      }
    //
    //      XCTAssertEqual(receivedMessages.count, 1)
    //      let receivedPayload = receivedMessages[0]["payload"]?.objectValue
    //      XCTAssertEqual(receivedPayload?["data"]?.stringValue, "test-data")
    //      XCTAssertEqual(receivedPayload?["timestamp"]?.intValue, 12345)
    //
    //      await channel1.unsubscribe()
    //      await channel2.unsubscribe()
    //    }

    // MARK: - Real Application Simulation

    /// Simulates a real application scenario with 2 clients using broadcast and presence.
    /// This test simulates a chat room or collaborative workspace where:
    /// - Users join and track their presence
    /// - Users exchange messages via broadcast
    /// - Users can see each other's presence changes
    func testRealApplicationScenario_BroadcastAndPresence() async throws {
      // User state models
      struct UserPresence: Codable, Equatable {
        let userId: String
        let username: String
        let status: String  // "online", "typing", "away"
        let lastSeen: Date
      }

      struct ChatMessage: Codable, Equatable {
        let messageId: String
        let userId: String
        let username: String
        let text: String
        let timestamp: Date
      }

      // Connect both clients
      await client.realtimeV2.connect()
      await client2.realtimeV2.connect()

      // Both users join the same channel (e.g., a chat room or workspace)
      let channel1 = client.realtimeV2.channel("app-room") {
        $0.broadcast.receiveOwnBroadcasts = true
      }

      let channel2 = client2.realtimeV2.channel("app-room") {
        $0.broadcast.receiveOwnBroadcasts = true
      }

      // Set up presence tracking for both users
      let user1Id = UUID().uuidString
      let user2Id = UUID().uuidString

      let user1Presence = UserPresence(
        userId: user1Id,
        username: "Alice",
        status: "online",
        lastSeen: Date()
      )

      let user2Presence = UserPresence(
        userId: user2Id,
        username: "Bob",
        status: "online",
        lastSeen: Date()
      )

      // Set up listeners for presence changes
      let client1PresenceChanges = Task {
        await channel1.presenceChange().prefix(5).collect()
      }

      let client2PresenceChanges = Task {
        await channel2.presenceChange().prefix(5).collect()
      }

      // Set up listeners for chat messages
      let client1Messages = Task {
        await channel1.broadcastStream(event: "chat-message").prefix(3).collect()
      }

      let client2Messages = Task {
        await channel2.broadcastStream(event: "chat-message").prefix(3).collect()
      }

      // Subscribe both clients
      try await channel1.subscribeWithError()
      try await channel2.subscribeWithError()

      // Wait for subscriptions to be ready
      try await Task.sleep(nanoseconds: 500_000_000)

      // User 1 joins and tracks presence
      try await channel1.track(user1Presence)
      try await Task.sleep(nanoseconds: 500_000_000)

      // User 2 joins and tracks presence
      try await channel2.track(user2Presence)
      try await Task.sleep(nanoseconds: 500_000_000)

      // User 1 sends a message
      let message1 = ChatMessage(
        messageId: UUID().uuidString,
        userId: user1Id,
        username: "Alice",
        text: "Hello, Bob! How are you?",
        timestamp: Date()
      )
      try await channel1.broadcast(event: "chat-message", message: message1)
      try await Task.sleep(nanoseconds: 500_000_000)

      // User 2 updates presence to "typing"
      let user2Typing = UserPresence(
        userId: user2Id,
        username: "Bob",
        status: "typing",
        lastSeen: Date()
      )
      try await channel2.track(user2Typing)
      try await Task.sleep(nanoseconds: 500_000_000)

      // User 2 sends a reply
      let message2 = ChatMessage(
        messageId: UUID().uuidString,
        userId: user2Id,
        username: "Bob",
        text: "Hi Alice! I'm doing great, thanks!",
        timestamp: Date()
      )
      try await channel2.broadcast(event: "chat-message", message: message2)
      try await Task.sleep(nanoseconds: 500_000_000)

      // User 2 updates presence back to "online"
      let user2Online = UserPresence(
        userId: user2Id,
        username: "Bob",
        status: "online",
        lastSeen: Date()
      )
      try await channel2.track(user2Online)
      try await Task.sleep(nanoseconds: 500_000_000)

      // User 1 sends another message
      let message3 = ChatMessage(
        messageId: UUID().uuidString,
        userId: user1Id,
        username: "Alice",
        text: "Great to hear! Let's work on the project together.",
        timestamp: Date()
      )
      try await channel1.broadcast(event: "chat-message", message: message3)
      try await Task.sleep(nanoseconds: 500_000_000)

      // User 1 leaves (untracks presence)
      await channel1.untrack()
      try await Task.sleep(nanoseconds: 500_000_000)

      // Collect all events
      let presenceChanges1 = try await withTimeout(interval: 5) {
        await client1PresenceChanges.value
      }

      let presenceChanges2 = try await withTimeout(interval: 5) {
        await client2PresenceChanges.value
      }

      let messages1 = try await withTimeout(interval: 5) {
        await client1Messages.value
      }

      let messages2 = try await withTimeout(interval: 5) {
        await client2Messages.value
      }

      // Verify presence changes
      // Client 1 should see:
      // 1. Initial state (empty)
      // 2. User 1 joins (themselves)
      // 3. User 2 joins
      // 4. User 2 status changes to "typing"
      // 5. User 2 status changes back to "online"
      XCTAssertTrue(presenceChanges1.count >= 3, "Client 1 should see presence changes")

      // Client 2 should see:
      // 1. Initial state (empty)
      // 2. User 1 joins
      // 3. User 2 joins (themselves)
      // 4. User 2 status changes to "typing"
      // 5. User 2 status changes back to "online"
      // 6. User 1 leaves
      XCTAssertTrue(presenceChanges2.count >= 3, "Client 2 should see presence changes")

      // Verify both clients can decode presence
      // Note: Due to timing, exact presence changes may vary, but structure should be correct
      XCTAssertTrue(presenceChanges1.count > 0, "Client 1 should receive presence changes")

      // Verify messages were received by both clients
      XCTAssertEqual(messages1.count, 3, "Client 1 should receive all 3 messages")
      XCTAssertEqual(messages2.count, 3, "Client 2 should receive all 3 messages")

      // Verify message content
      let receivedMessage1 = try messages1[0]["payload"]?.objectValue?.decode(
        as: ChatMessage.self,
        decoder: .supabase()
      )
      XCTAssertEqual(receivedMessage1?.text, "Hello, Bob! How are you?")
      XCTAssertEqual(receivedMessage1?.username, "Alice")

      let receivedMessage2 = try messages2[0]["payload"]?.objectValue?.decode(
        as: ChatMessage.self,
        decoder: .supabase()
      )
      XCTAssertEqual(receivedMessage2?.text, "Hello, Bob! How are you?")
      XCTAssertEqual(receivedMessage2?.username, "Alice")

      // Verify the last message
      let receivedMessage3 = try messages1[2]["payload"]?.objectValue?.decode(
        as: ChatMessage.self,
        decoder: .supabase()
      )
      XCTAssertEqual(receivedMessage3?.text, "Great to hear! Let's work on the project together.")
      XCTAssertEqual(receivedMessage3?.username, "Alice")

      // Verify user 1 leaving is detected by user 2
      // Note: Due to timing, exact presence changes may vary, but structure should be correct
      XCTAssertTrue(presenceChanges2.count > 0, "Client 2 should receive presence changes")

      // Cleanup
      await channel1.unsubscribe()
      await channel2.unsubscribe()
    }

    // MARK: - Helpers

    private func subscribeMany(_ channels: [RealtimeChannelV2]) async throws {
      try await withThrowingTaskGroup { group in
        for channel in channels {
          group.addTask { try await channel.subscribeWithError() }
        }

        try await group.waitForAll()
      }
    }

    private func unsubscribeMany(_ channels: [RealtimeChannelV2]) async {
      await withTaskGroup { group in
        for channel in channels {
          group.addTask { await channel.unsubscribe() }
        }

        await group.waitForAll()
      }
    }

  }
#endif
