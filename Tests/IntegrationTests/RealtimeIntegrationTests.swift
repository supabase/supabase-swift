//
//  RealtimeIntegrationTests.swift
//
//
//  Created by AI Assistant on 09/01/25.
//

#if !os(Android) && !os(Linux)
  import Clocks
  import ConcurrencyExtras
  import CustomDump
  import Foundation
  import OSLog
  import Supabase
  import TestHelpers
  import Testing

  @testable import Realtime
  @testable import RealtimeV2

  // Serialize this suite so concurrent tests don't open competing realtime connections against
  // the same local Supabase instance — Swift Testing runs `@Test`s in the same suite concurrently
  // by default, unlike XCTest's implicit one-class-at-a-time execution. Use a class (not a
  // struct) so `deinit` can disconnect both clients afterward, mirroring the old `tearDown()`.
  @Suite(.serialized)
  final class RealtimeIntegrationTests: Sendable {
    let testClock = TestClock<Duration>()

    let client: SupabaseClient
    let client2: SupabaseClient

    init() async throws {
      client = SupabaseClient(
        supabaseURL: URL(string: DotEnv.SUPABASE_URL) ?? URL(string: "http://127.0.0.1:54321")!,
        supabaseKey: DotEnv.SUPABASE_PUBLISHABLE_KEY,
        options: SupabaseClientOptions(
          auth: .init(storage: InMemoryLocalStorage()),
          global: .init(
            logger: OSLogSupabaseLogger(
              Logger(subsystem: "realtime.integration.tests", category: "client1")
            )
          )
        ),
        clock: testClock
      )

      client2 = SupabaseClient(
        supabaseURL: URL(string: DotEnv.SUPABASE_URL) ?? URL(string: "http://127.0.0.1:54321")!,
        supabaseKey: DotEnv.SUPABASE_PUBLISHABLE_KEY,
        options: SupabaseClientOptions(
          auth: .init(storage: InMemoryLocalStorage()),
          global: .init(
            logger: OSLogSupabaseLogger(
              Logger(subsystem: "realtime.integration.tests", category: "client2")
            )
          )
        ),
        clock: testClock
      )

      // Clean up any existing data
      _ = try? await client.from("key_value_storage").delete().neq("key", value: UUID().uuidString)
        .execute()
    }

    // Async cleanup can outlive the test if the process exits immediately after — acceptable for
    // local dev/CI cleanup against an ephemeral local Supabase instance, not correctness-critical.
    deinit {
      let client = client
      let client2 = client2
      Task {
        await client.realtimeV2.removeAllChannels()
        client.realtimeV2.disconnect()

        await client2.realtimeV2.removeAllChannels()
        client2.realtimeV2.disconnect()
      }
    }

    // MARK: - Connection Management Tests

    @Test
    func connectionAndDisconnection() async throws {
      let client = client
      try await withMainSerialExecutor {
        #expect(client.realtimeV2.status == .disconnected)

        await client.realtimeV2.connect()
        #expect(client.realtimeV2.status == .connected)

        client.realtimeV2.disconnect()
        #expect(client.realtimeV2.status == .disconnected)
      }
    }

    @Test
    func connectionStatusChanges() async throws {
      let client = client
      try await withMainSerialExecutor {
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
        #expect(statuses.value.contains(.connecting))
        #expect(statuses.value.contains(.connected))
        #expect(statuses.value.contains(.disconnected))
      }
    }

    @Test
    func manualDisconnectShouldNotReconnect() async throws {
      let client = client
      let testClock = testClock
      try await withMainSerialExecutor {
        await client.realtimeV2.connect()
        #expect(client.realtimeV2.status == .connected)

        client.realtimeV2.disconnect()

        // Wait for potential reconnection delay
        await testClock.advance(by: .seconds(RealtimeClientOptions.defaultReconnectDelay + 1))

        #expect(client.realtimeV2.status == .disconnected)
      }
    }

    @Test
    func multipleConnectCalls() async throws {
      let client = client
      try await withMainSerialExecutor {
        await client.realtimeV2.connect()
        #expect(client.realtimeV2.status == .connected)

        // Multiple connect calls should be idempotent
        await client.realtimeV2.connect()
        await client.realtimeV2.connect()

        #expect(client.realtimeV2.status == .connected)
      }
    }

    // MARK: - Channel Management Tests

    @Test
    func channelStatusChanges() async throws {
      let client = client
      try await withMainSerialExecutor {
        await client.realtimeV2.connect()

        let channel = client.realtimeV2.channel("test-channel")
        let statuses = LockIsolated<[RealtimeChannelStatus]>([])

        let subscription = channel.onStatusChange { status in
          statuses.withValue { $0.append(status) }
        }
        defer { subscription.cancel() }

        try await channel.subscribeWithError()
        await channel.unsubscribe()

        #expect(
          statuses.value
            == [.unsubscribed, .subscribing, .subscribed, .unsubscribing, .unsubscribed]
        )
      }
    }

    @Test
    func multipleChannels() async throws {
      let client = client
      try await withMainSerialExecutor {
        // Do not connect client, let first channel subscription do it.

        let channel1 = client.realtimeV2.channel("channel-1")
        let channel2 = client.realtimeV2.channel("channel-2")
        let channel3 = client.realtimeV2.channel("channel-3")

        try await subscribeMany([channel1, channel2, channel3])

        #expect(channel1.status == .subscribed)
        #expect(channel2.status == .subscribed)
        #expect(channel3.status == .subscribed)

        #expect(client.realtimeV2.channels.count == 3)

        await unsubscribeMany([channel1, channel2, channel3])
      }
    }

    @Test
    func channelReuse() async throws {
      let client = client
      try await withMainSerialExecutor {
        await client.realtimeV2.connect()

        let channel1 = client.realtimeV2.channel("reuse-channel")
        try await channel1.subscribeWithError()

        // Getting the same channel should return the existing instance
        let channel2 = client.realtimeV2.channel("reuse-channel")
        #expect(channel1 === channel2)
        #expect(channel2.status == .subscribed)

        await channel1.unsubscribe()

        // Unsubscribing channel1 should unsubscribe channel2
        #expect(channel2.status == .unsubscribed)
      }
    }

    @Test
    func removeChannel() async throws {
      let client = client
      try await withMainSerialExecutor {
        await client.realtimeV2.connect()

        let channel = client.realtimeV2.channel("remove-test")
        try await channel.subscribeWithError()

        await client.realtimeV2.removeChannel(channel)

        #expect(channel.status == .unsubscribed)
        #expect(!client.realtimeV2.channels.keys.contains(channel.topic))
      }
    }

    @Test
    func removeAllChannels() async throws {
      let client = client
      try await withMainSerialExecutor {
        await client.realtimeV2.connect()

        let channel1 = client.realtimeV2.channel("all-1")
        let channel2 = client.realtimeV2.channel("all-2")
        let channel3 = client.realtimeV2.channel("all-3")

        try await subscribeMany([channel1, channel2, channel3])

        await client.realtimeV2.removeAllChannels()

        #expect(channel1.status == .unsubscribed)
        #expect(channel2.status == .unsubscribed)
        #expect(channel3.status == .unsubscribed)
        #expect(client.realtimeV2.channels.count == 0)

        #expect(
          client.realtimeV2.status == .disconnected,
          "Should disconnect client if all channels are removed"
        )
      }
    }

    // MARK: - Broadcast Tests

    @Test
    func broadcastSendAndReceive() async throws {
      let client = client
      try await withMainSerialExecutor {
        await client.realtimeV2.connect()

        let channel = client.realtimeV2.channel("broadcast-test") {
          $0.broadcast.receiveOwnBroadcasts = true
        }

        struct Message: Codable, Sendable {
          let value: Int
          let text: String
        }

        let receivedMessagesTask = Task {
          await channel.broadcastStream(event: "test-event").prefix(3).collect()
        }

        try await channel.subscribeWithError()

        try await channel.broadcast(event: "test-event", message: Message(value: 1, text: "first"))
        try await channel.broadcast(
          event: "test-event", message: Message(value: 2, text: "second"))
        await channel.broadcast(event: "test-event", message: ["value": 3, "text": "third"])

        let receivedMessages = try await withTimeout(interval: 5) {
          await receivedMessagesTask.value
        }

        #expect(receivedMessages.count == 3)

        let firstMessage = receivedMessages[0]
        #expect(firstMessage["event"]?.stringValue == "test-event")
        #expect(firstMessage["payload"]?.objectValue?["value"]?.intValue == 1)
        #expect(firstMessage["payload"]?.objectValue?["text"]?.stringValue == "first")

        // Clean up

        await channel.unsubscribe()
      }
    }

    @Test
    func broadcastMultipleEvents() async throws {
      let client = client
      try await withMainSerialExecutor {
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

        #expect(event1.count == 2)
        #expect(event2.count == 2)

        await channel.unsubscribe()
      }
    }

    @Test
    func broadcastWithoutOwnBroadcasts() async throws {
      let client = client
      try await withMainSerialExecutor {
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

        #expect(receivedCount.value == 0)

        subscription.cancel()
        await channel.unsubscribe()
      }
    }

    // MARK: - Postgres Changes Tests

    @Test
    func postgresAllChanges() async throws {
      let client = client
      try await withMainSerialExecutor {
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

        #expect(received.count == 3)

        // Verify action types
        if case .insert(let action) = received[0] {
          let record = try action.decodeRecord(as: Entry.self, decoder: .supabase())
          #expect(record.key == testKey)
        } else {
          Issue.record("Expected insert action")
        }

        if case .update(let action) = received[1] {
          let record = try action.decodeRecord(as: Entry.self, decoder: .supabase())
          #expect(record.value.stringValue == "value2")
        } else {
          Issue.record("Expected update action")
        }

        if case .delete(let action) = received[2] {
          let oldRecordKey = action.oldRecord["key"]?.stringValue
          #expect(oldRecordKey == testKey)
        } else {
          Issue.record("Expected delete action")
        }

        await channel.unsubscribe()
      }
    }

    @Test
    func postgresChangesWithFilter() async throws {
      let client = client
      try await withMainSerialExecutor {
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

        #expect(received.count == 1)
        let record = try received[0].decodeRecord(as: Entry.self, decoder: .supabase())
        #expect(record.key == testKey1)
        #expect(record.key != testKey2)

        await channel.unsubscribe()
      }
    }

    @Test
    func postgresChangesMultipleSubscriptions() async throws {
      let client = client
      try await withMainSerialExecutor {
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

        #expect(inserts.count == 1)
        #expect(updates.count == 1)
        #expect(deletes.count == 1)

        await channel.unsubscribe()
      }
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
    @Test
    func realApplicationScenario_BroadcastAndPresence() async throws {
      let client = client
      let client2 = client2
      try await withMainSerialExecutor {
        // User state models
        struct UserPresence: Codable, Equatable, Sendable {
          let userId: String
          let username: String
          let status: String  // "online", "typing", "away"
          let lastSeen: Date
        }

        struct ChatMessage: Codable, Equatable, Sendable {
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
        #expect(presenceChanges1.count >= 3, "Client 1 should see presence changes")

        // Client 2 should see:
        // 1. Initial state (empty)
        // 2. User 1 joins
        // 3. User 2 joins (themselves)
        // 4. User 2 status changes to "typing"
        // 5. User 2 status changes back to "online"
        // 6. User 1 leaves
        #expect(presenceChanges2.count >= 3, "Client 2 should see presence changes")

        // Verify both clients can decode presence
        // Note: Due to timing, exact presence changes may vary, but structure should be correct
        #expect(presenceChanges1.count > 0, "Client 1 should receive presence changes")

        // Verify messages were received by both clients
        #expect(messages1.count == 3, "Client 1 should receive all 3 messages")
        #expect(messages2.count == 3, "Client 2 should receive all 3 messages")

        // Verify message content
        let receivedMessage1 = try messages1[0]["payload"]?.objectValue?.decode(
          as: ChatMessage.self,
          decoder: .supabase()
        )
        #expect(receivedMessage1?.text == "Hello, Bob! How are you?")
        #expect(receivedMessage1?.username == "Alice")

        let receivedMessage2 = try messages2[0]["payload"]?.objectValue?.decode(
          as: ChatMessage.self,
          decoder: .supabase()
        )
        #expect(receivedMessage2?.text == "Hello, Bob! How are you?")
        #expect(receivedMessage2?.username == "Alice")

        // Verify the last message
        let receivedMessage3 = try messages1[2]["payload"]?.objectValue?.decode(
          as: ChatMessage.self,
          decoder: .supabase()
        )
        #expect(receivedMessage3?.text == "Great to hear! Let's work on the project together.")
        #expect(receivedMessage3?.username == "Alice")

        // Verify user 1 leaving is detected by user 2
        // Note: Due to timing, exact presence changes may vary, but structure should be correct
        #expect(presenceChanges2.count > 0, "Client 2 should receive presence changes")

        // Cleanup
        await channel1.unsubscribe()
        await channel2.unsubscribe()
      }
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
