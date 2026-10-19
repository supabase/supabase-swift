//
//  RealtimeIntegrationTests.swift
//
//
//  Created by AI Assistant on 09/01/25.
//

// Linux: the official Swift images' libcurl is built without WebSocket support, so
// `URLSessionWebSocketTask` fails with "WebSockets not supported by libcurl" and the client never
// connects.
#if !os(Android) && !os(Linux)
  import Clocks
  import ConcurrencyExtras
  import CustomDump
  import Foundation
  import Logging
  import OSLog
  import Supabase
  import TestHelpers
  import Testing

  @testable import Helpers
  @testable import Realtime

  @Suite(
    .serialized,
    .mainSerialExecutorSerialized,
    .timeLimit(.minutes(1)),
    .enabled(if: ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil)
  )
  final class RealtimeIntegrationTests: Sendable {
    let testClock = TestClock<Duration>()

    let client: SupabaseClient
    let client2: SupabaseClient

    init() async throws {
      client = SupabaseClient(
        supabaseURL: URL(string: DotEnv.supabaseURL) ?? URL(string: "http://127.0.0.1:54321")!,
        supabaseKey: DotEnv.supabasePublishableKey,
        options: SupabaseClientOptions(
          auth: .init(storage: InMemoryLocalStorage()),
          global: .init(
            logger: Logging.Logger(label: "client1") {
              OSLogHandler(label: $0, subsystem: "realtime.integration.tests")
            },
            clock: testClock
          )
        )
      )

      client2 = SupabaseClient(
        supabaseURL: URL(string: DotEnv.supabaseURL) ?? URL(string: "http://127.0.0.1:54321")!,
        supabaseKey: DotEnv.supabasePublishableKey,
        options: SupabaseClientOptions(
          auth: .init(storage: InMemoryLocalStorage()),
          global: .init(
            logger: Logging.Logger(label: "client2") {
              OSLogHandler(label: $0, subsystem: "realtime.integration.tests")
            },
            clock: testClock
          )
        )
      )

      _ = try? await client.from("key_value_storage").delete().neq("key", value: UUID().uuidString)
        .execute()
    }

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

        await Task.megaYield()

        subscription.cancel()

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

        await testClock.advance(by: RealtimeClientOptions.defaultReconnectDelay + .seconds(1))

        #expect(client.realtimeV2.status == .disconnected)
      }
    }

    @Test
    func multipleConnectCalls() async throws {
      let client = client
      try await withMainSerialExecutor {
        await client.realtimeV2.connect()
        #expect(client.realtimeV2.status == .connected)

        await client.realtimeV2.connect()
        await client.realtimeV2.connect()

        #expect(client.realtimeV2.status == .connected)
      }
    }

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

        let channel2 = client.realtimeV2.channel("reuse-channel")
        #expect(channel1 === channel2)
        #expect(channel2.status == .subscribed)

        await channel1.unsubscribe()

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

        let receivedMessagesStream = channel.broadcastStream(event: "test-event")

        try await channel.subscribeWithError()

        try await channel.broadcast(event: "test-event", message: Message(value: 1, text: "first"))
        try await channel.broadcast(
          event: "test-event", message: Message(value: 2, text: "second"))
        await channel.broadcast(event: "test-event", message: ["value": 3, "text": "third"])

        let receivedMessages = try await withTimeout(.seconds(5)) {
          await receivedMessagesStream.prefix(3).collect()
        }

        #expect(receivedMessages.count == 3)

        let firstMessage = receivedMessages[0]
        #expect(firstMessage["event"]?.stringValue == "test-event")
        #expect(firstMessage["payload"]?.objectValue?["value"]?.intValue == 1)
        #expect(firstMessage["payload"]?.objectValue?["text"]?.stringValue == "first")

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

        let event1Messages = channel.broadcastStream(event: "event-1")
        let event2Messages = channel.broadcastStream(event: "event-2")

        try await channel.subscribeWithError()

        try await channel.broadcast(event: "event-1", message: ["data": "1"])
        try await channel.broadcast(event: "event-2", message: ["data": "2"])
        try await channel.broadcast(event: "event-1", message: ["data": "3"])
        try await channel.broadcast(event: "event-2", message: ["data": "4"])

        let event1 = try await withTimeout(.seconds(5)) {
          await event1Messages.prefix(2).collect()
        }

        let event2 = try await withTimeout(.seconds(5)) {
          await event2Messages.prefix(2).collect()
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

        try await channel.broadcast(event: "test", message: ["data": "test"])

        try await Task.sleep(nanoseconds: 500_000_000)

        #expect(receivedCount.value == 0)

        subscription.cancel()
        await channel.unsubscribe()
      }
    }

    @Test
    func postgresAllChanges() async throws {
      let client = client
      try await withMainSerialExecutor {
        await client.realtimeV2.connect()

        let channel = client.realtimeV2.channel("postgres-all")

        struct Entry: Codable, Equatable {
          let key: String
          let value: JSONValue
        }

        let allChanges = channel.postgresChange(
          AnyAction.self, schema: "public", table: "key_value_storage")
        let system = channel.system()

        try await channel.subscribeWithError()

        _ = try await withTimeout(.seconds(10)) {
          await system.first(where: { _ in true })
        }

        let testKey = UUID().uuidString

        _ = try await client.from("key_value_storage")
          .insert(["key": testKey, "value": "value1"]).select().single().execute()

        try await Task.sleep(nanoseconds: 500_000_000)

        try await client.from("key_value_storage").update(["value": "value2"]).eq(
          "key",
          value: testKey
        )
        .execute()

        try await Task.sleep(nanoseconds: 500_000_000)

        try await client.from("key_value_storage").delete().eq("key", value: testKey).execute()

        let received = try await withTimeout(.seconds(5)) {
          await allChanges.prefix(3).collect()
        }

        #expect(received.count == 3)

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
          let value: JSONValue
        }

        let testKey1 = UUID().uuidString
        let testKey2 = UUID().uuidString

        let filtered = channel.postgresChange(
          InsertAction.self,
          schema: "public",
          table: "key_value_storage",
          filter: .eq("key", value: testKey1)
        )
        let system = channel.system()

        try await channel.subscribeWithError()

        _ = try await withTimeout(.seconds(10)) {
          await system.first(where: { _ in true })
        }

        _ = try await client.from("key_value_storage")
          .insert(["key": testKey1, "value": "filtered"]).select().single().execute()

        try await Task.sleep(nanoseconds: 500_000_000)

        _ = try await client.from("key_value_storage")
          .insert(["key": testKey2, "value": "not-filtered"]).select().single().execute()

        let received = try await withTimeout(.seconds(5)) {
          await filtered.prefix(1).collect()
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
          let value: JSONValue
        }

        let insertions = channel.postgresChange(
          InsertAction.self, schema: "public", table: "key_value_storage")
        let updates = channel.postgresChange(
          UpdateAction.self, schema: "public", table: "key_value_storage")
        let deletions = channel.postgresChange(
          DeleteAction.self, schema: "public", table: "key_value_storage")
        let system = channel.system()

        try await channel.subscribeWithError()

        _ = try await withTimeout(.seconds(10)) {
          await system.first(where: { _ in true })
        }

        let testKey = UUID().uuidString

        _ = try await client.from("key_value_storage")
          .insert(["key": testKey, "value": "value1"]).select().single().execute()

        try await Task.sleep(nanoseconds: 500_000_000)

        try await client.from("key_value_storage").update(["value": "value2"]).eq(
          "key",
          value: testKey
        )
        .execute()

        try await Task.sleep(nanoseconds: 500_000_000)

        try await client.from("key_value_storage").delete().eq("key", value: testKey).execute()

        let inserted = try await withTimeout(.seconds(5)) {
          await insertions.prefix(1).collect()
        }

        let updated = try await withTimeout(.seconds(5)) {
          await updates.prefix(1).collect()
        }

        let deleted = try await withTimeout(.seconds(5)) {
          await deletions.prefix(1).collect()
        }

        #expect(inserted.count == 1)
        #expect(updated.count == 1)
        #expect(deleted.count == 1)

        await channel.unsubscribe()
      }
    }

    @Test
    func realApplicationScenario_BroadcastAndPresence() async throws {
      let client = client
      let client2 = client2
      try await withMainSerialExecutor {
        struct UserPresence: Codable, Equatable, Sendable {
          let userId: String
          let username: String
          let status: String
          let lastSeen: Date
        }

        struct ChatMessage: Codable, Equatable, Sendable {
          let messageId: String
          let userId: String
          let username: String
          let text: String
          let timestamp: Date
        }

        await client.realtimeV2.connect()
        await client2.realtimeV2.connect()

        let channel1 = client.realtimeV2.channel("app-room") {
          $0.broadcast.receiveOwnBroadcasts = true
        }

        let channel2 = client2.realtimeV2.channel("app-room") {
          $0.broadcast.receiveOwnBroadcasts = true
        }

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

        let client1PresenceChanges = channel1.presenceChange()
        let client2PresenceChanges = channel2.presenceChange()

        let client1Messages = channel1.broadcastStream(event: "chat-message")
        let client2Messages = channel2.broadcastStream(event: "chat-message")

        try await channel1.subscribeWithError()
        try await channel2.subscribeWithError()

        try await Task.sleep(nanoseconds: 500_000_000)

        try await channel1.track(user1Presence)
        try await Task.sleep(nanoseconds: 500_000_000)

        try await channel2.track(user2Presence)
        try await Task.sleep(nanoseconds: 500_000_000)

        let message1 = ChatMessage(
          messageId: UUID().uuidString,
          userId: user1Id,
          username: "Alice",
          text: "Hello, Bob! How are you?",
          timestamp: Date()
        )
        try await channel1.broadcast(event: "chat-message", message: message1)
        try await Task.sleep(nanoseconds: 500_000_000)

        let user2Typing = UserPresence(
          userId: user2Id,
          username: "Bob",
          status: "typing",
          lastSeen: Date()
        )
        try await channel2.track(user2Typing)
        try await Task.sleep(nanoseconds: 500_000_000)

        let message2 = ChatMessage(
          messageId: UUID().uuidString,
          userId: user2Id,
          username: "Bob",
          text: "Hi Alice! I'm doing great, thanks!",
          timestamp: Date()
        )
        try await channel2.broadcast(event: "chat-message", message: message2)
        try await Task.sleep(nanoseconds: 500_000_000)

        let user2Online = UserPresence(
          userId: user2Id,
          username: "Bob",
          status: "online",
          lastSeen: Date()
        )
        try await channel2.track(user2Online)
        try await Task.sleep(nanoseconds: 500_000_000)

        let message3 = ChatMessage(
          messageId: UUID().uuidString,
          userId: user1Id,
          username: "Alice",
          text: "Great to hear! Let's work on the project together.",
          timestamp: Date()
        )
        try await channel1.broadcast(event: "chat-message", message: message3)
        try await Task.sleep(nanoseconds: 500_000_000)

        await channel1.untrack()
        try await Task.sleep(nanoseconds: 500_000_000)

        let presenceChanges1 = try await withTimeout(.seconds(5)) {
          await client1PresenceChanges.prefix(5).collect()
        }

        let presenceChanges2 = try await withTimeout(.seconds(5)) {
          await client2PresenceChanges.prefix(5).collect()
        }

        let messages1 = try await withTimeout(.seconds(5)) {
          await client1Messages.prefix(3).collect()
        }

        let messages2 = try await withTimeout(.seconds(5)) {
          await client2Messages.prefix(3).collect()
        }

        #expect(presenceChanges1.count >= 3, "Client 1 should see presence changes")

        #expect(presenceChanges2.count >= 3, "Client 2 should see presence changes")

        #expect(presenceChanges1.count > 0, "Client 1 should receive presence changes")

        #expect(messages1.count == 3, "Client 1 should receive all 3 messages")
        #expect(messages2.count == 3, "Client 2 should receive all 3 messages")

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

        let receivedMessage3 = try messages1[2]["payload"]?.objectValue?.decode(
          as: ChatMessage.self,
          decoder: .supabase()
        )
        #expect(receivedMessage3?.text == "Great to hear! Let's work on the project together.")
        #expect(receivedMessage3?.username == "Alice")

        #expect(presenceChanges2.count > 0, "Client 2 should receive presence changes")

        await channel1.unsubscribe()
        await channel2.unsubscribe()
      }
    }

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
