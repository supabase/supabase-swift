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
    // `subscribe()` times out on `testClock`, which never advances, so a stack that is
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
        await client.realtime.removeAllChannels()
        await client.realtime.disconnect()
        await client2.realtime.removeAllChannels()
        await client2.realtime.disconnect()
      }
    }

    @Test
    func connectionAndDisconnection() async throws {
      let client = client
      try await withMainSerialExecutor {
        #expect(await client.realtime.status == .disconnected)

        try await client.realtime.connect()
        #expect(await client.realtime.status == .connected)

        await client.realtime.disconnect()
        #expect(await client.realtime.status == .disconnected)
      }
    }

    @Test
    func connectionStatusChanges() async throws {
      let client = client
      try await withMainSerialExecutor {
        let statuses = LockIsolated<[RealtimeClientStatus]>([])

        let statusChanges = await client.realtime.statusChanges()
        let observer = Task {
          for await status in statusChanges {
            statuses.withValue { $0.append(status) }
            if status == .disconnected, statuses.value.contains(.connected) { return }
          }
        }

        try await client.realtime.connect()
        await client.realtime.disconnect()

        await observer.value

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
        try await client.realtime.connect()
        #expect(await client.realtime.status == .connected)

        await client.realtime.disconnect()

        await testClock.advance(by: .seconds(2))

        #expect(await client.realtime.status == .disconnected)
      }
    }

    @Test
    func multipleConnectCalls() async throws {
      let client = client
      try await withMainSerialExecutor {
        try await client.realtime.connect()
        #expect(await client.realtime.status == .connected)

        try await client.realtime.connect()
        try await client.realtime.connect()

        #expect(await client.realtime.status == .connected)
      }
    }

    @Test
    func channelStatusChanges() async throws {
      let client = client
      try await withMainSerialExecutor {
        try await client.realtime.connect()

        let channel = await client.realtime.channel("test-channel")
        let statuses = LockIsolated<[RealtimeChannelStatus]>([])

        let statusChanges = await channel.statusChanges()
        let observer = Task {
          for await status in statusChanges {
            statuses.withValue { $0.append(status) }
            if status == .unsubscribed, statuses.value.contains(.subscribed) { return }
          }
        }

        try await channel.subscribe()
        await channel.unsubscribe()
        await observer.value

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

        let channel1 = await client.realtime.channel("channel-1")
        let channel2 = await client.realtime.channel("channel-2")
        let channel3 = await client.realtime.channel("channel-3")

        try await subscribeMany([channel1, channel2, channel3])

        #expect(await channel1.status == .subscribed)
        #expect(await channel2.status == .subscribed)
        #expect(await channel3.status == .subscribed)

        #expect(await client.realtime.channels.count == 3)

        await unsubscribeMany([channel1, channel2, channel3])
      }
    }

    @Test
    func channelReuse() async throws {
      let client = client
      try await withMainSerialExecutor {
        try await client.realtime.connect()

        let channel1 = await client.realtime.channel("reuse-channel")
        try await channel1.subscribe()

        let channel2 = await client.realtime.channel("reuse-channel")
        #expect(channel1 === channel2)
        #expect(await channel2.status == .subscribed)

        await channel1.unsubscribe()

        #expect(await channel2.status == .unsubscribed)
      }
    }

    @Test
    func removeChannel() async throws {
      let client = client
      try await withMainSerialExecutor {
        try await client.realtime.connect()

        let channel = await client.realtime.channel("remove-test")
        try await channel.subscribe()

        await client.realtime.removeChannel(channel)

        #expect(await channel.status == .unsubscribed)
        let topics = await client.realtime.channels.map(\.topic)
        #expect(!topics.contains(channel.topic))
      }
    }

    @Test
    func removeAllChannels() async throws {
      let client = client
      try await withMainSerialExecutor {
        try await client.realtime.connect()

        let channel1 = await client.realtime.channel("all-1")
        let channel2 = await client.realtime.channel("all-2")
        let channel3 = await client.realtime.channel("all-3")

        try await subscribeMany([channel1, channel2, channel3])

        await client.realtime.removeAllChannels()

        #expect(await channel1.status == .unsubscribed)
        #expect(await channel2.status == .unsubscribed)
        #expect(await channel3.status == .unsubscribed)
        #expect(await client.realtime.channels.count == 0)

        #expect(
          await client.realtime.status == .disconnected,
          "Should disconnect client if all channels are removed"
        )
      }
    }

    @Test
    func broadcastSendAndReceive() async throws {
      let client = client
      try await withMainSerialExecutor {
        try await client.realtime.connect()

        let channel = await client.realtime.channel("broadcast-test") {
          $0.broadcast.receiveOwnBroadcasts = true
        }

        struct Message: Codable, Sendable {
          let value: Int
          let text: String
        }

        let receivedMessagesStream = await channel.broadcasts(event: "test-event")

        try await channel.subscribe()

        try await channel.broadcast(event: "test-event", message: Message(value: 1, text: "first"))
        try await channel.broadcast(
          event: "test-event", message: Message(value: 2, text: "second"))
        try await channel.broadcast(
          event: "test-event", message: ["value": 3, "text": "third"] as JSONObject)

        let receivedMessages = try await withTimeout(.seconds(5)) {
          await receivedMessagesStream.prefix(3).collect()
        }

        #expect(receivedMessages.count == 3)

        let firstMessage = receivedMessages[0]
        #expect(firstMessage.event == "test-event")
        let decoded = try firstMessage.decode(as: Message.self)
        #expect(decoded.value == 1)
        #expect(decoded.text == "first")

        await channel.unsubscribe()
      }
    }

    @Test
    func customOptionsConnectSubscribeAndReceive() async throws {
      let realtime = RealtimeClient(
        url: URL(string: DotEnv.supabaseURL)!.appendingPathComponent("realtime/v1"),
        options: RealtimeClientOptions(
          headers: [
            "apikey": DotEnv.supabasePublishableKey,
            "Authorization": "Bearer \(DotEnv.supabasePublishableKey)",
          ],
          requestTimeout: .seconds(10),
          serverLogLevel: .warning,
          webSocketTransport: URLSessionWebSocketTransport(configuration: .ephemeral),
          handleAppLifecycle: false
        )
      )
      try await withMainSerialExecutor {
        try await realtime.connect()

        let channel = await realtime.channel("custom-options-\(UUID().uuidString)") {
          $0.broadcast.receiveOwnBroadcasts = true
        }
        let received = await channel.broadcasts(event: "ping")
        try await channel.subscribe()

        try await channel.broadcast(event: "ping", message: ["value": 1] as JSONObject)

        let messages = try await withTimeout(.seconds(5)) {
          await received.prefix(1).collect()
        }
        #expect(try messages.first?.decode(as: [String: Int].self) == ["value": 1])
        #expect(await realtime.channels.count == 1)

        await realtime.removeAllChannels()
        #expect(await realtime.channels.isEmpty)
        #expect(await realtime.status == .disconnected)
      }
    }

    @Test
    func binaryBroadcastArrivesAsBinaryPayload() async throws {
      let client = client
      try await withMainSerialExecutor {
        try await client.realtime.connect()

        let channel = await client.realtime.channel("broadcast-binary") {
          $0.broadcast.receiveOwnBroadcasts = true
        }
        let messages = await channel.broadcasts(event: "bytes")
        try await channel.subscribe()

        let bytes = Data([0x00, 0xCA, 0xFE, 0xFF])
        try await channel.broadcast(event: "bytes", data: bytes)
        let received = try await withTimeout(.seconds(5)) {
          await messages.first(where: { _ in true })
        }

        #expect(received?.event == "bytes")
        #expect(received?.payload == .binary(bytes))
        await channel.unsubscribe()
      }
    }

    @Test
    func aNewTokenIsSentToSubscribedChannelsAndTheServerKeepsThem() async throws {
      let client = client
      try await withMainSerialExecutor {
        try await client.realtime.connect()

        let channel = await client.realtime.channel("access-token-test") {
          $0.broadcast.receiveOwnBroadcasts = true
        }
        let messages = await channel.broadcasts(event: "after-token")
        try await channel.subscribe()

        let session = try await client.auth.signUp(
          email: "realtime-\(UUID().uuidString.lowercased())@supabase.com",
          password: "The.Pass.123"
        ).session
        let accessToken = try #require(session?.accessToken)
        await client.realtime.setAuth(accessToken)
        #expect(await client.realtime.accessToken == accessToken)

        try await channel.broadcast(event: "after-token", message: ["value": 1] as JSONObject)
        let received = try await withTimeout(.seconds(5)) {
          await messages.first(where: { _ in true })
        }

        #expect(received?.payload == .json(["value": 1]))
        #expect(await channel.status == .subscribed)
        await channel.unsubscribe()
      }
    }

    @Test
    func aSignInPushesTheSessionTokenToAnExistingRealtimeClient() async throws {
      let realtime = client.realtime

      let session = try await client.auth.signUp(
        email: "realtime-\(UUID().uuidString.lowercased())@supabase.com",
        password: "The.Pass.123"
      ).session
      let accessToken = try #require(session?.accessToken)

      let pushed = try await withTimeout(.seconds(5)) {
        while !Task.isCancelled, await realtime.accessToken != accessToken {
          await Task.yield()
        }
        return await realtime.accessToken == accessToken
      }
      #expect(pushed)
    }

    @Test
    func broadcastMultipleEvents() async throws {
      let client = client
      try await withMainSerialExecutor {
        try await client.realtime.connect()

        let channel = await client.realtime.channel("broadcast-multi") {
          $0.broadcast.receiveOwnBroadcasts = true
        }

        let event1Messages = await channel.broadcasts(event: "event-1")
        let event2Messages = await channel.broadcasts(event: "event-2")

        try await channel.subscribe()

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
        try await client.realtime.connect()

        let channel = await client.realtime.channel("broadcast-no-own") {
          $0.broadcast.receiveOwnBroadcasts = false
        }

        let receivedCount = LockIsolated<Int>(0)
        let broadcasts = await channel.broadcasts(event: "test")
        let subscription = Task {
          for await _ in broadcasts {
            receivedCount.withValue { $0 += 1 }
          }
        }

        try await channel.subscribe()

        try await channel.broadcast(event: "test", message: ["data": "test"])

        try await Task.sleep(nanoseconds: 500_000_000)

        #expect(receivedCount.value == 0)

        subscription.cancel()
        await channel.unsubscribe()
      }
    }

    /// No RLS policy on `realtime.messages` lets the anon role read a private channel, so the
    /// server refuses the join. `testClock` never advances: `subscribe()` must throw on the
    /// refusal itself, not after a timeout.
    @Test
    func privateChannelWithoutAPolicyFailsAtOnce() async throws {
      let client = client
      try await withMainSerialExecutor {
        try await client.realtime.connect()

        let channel = await client.realtime.channel("private-denied") {
          $0.isPrivate = true
        }

        let error = await #expect(throws: RealtimeError.self) { try await channel.subscribe() }
        #expect(error?.kind == .unauthorized)
        #expect(error?.serverCode == .unauthorized)
        #expect(error?.isRetryable == false)
        #expect(await channel.status == .failed)
        #expect(await channel.status.error?.serverCode == .unauthorized)
      }
    }

    @Test
    func postgresAllChanges() async throws {
      let client = client
      try await withMainSerialExecutor {
        try await client.realtime.connect()

        let channel = await client.realtime.channel("postgres-all")

        struct Entry: Codable, Equatable {
          let key: String
          let value: JSONValue
        }

        let allChanges = await channel.postgresChanges(
          of: Entry.self, schema: "public", table: "key_value_storage")
        let events = await channel.events()

        try await channel.subscribe()

        _ = try await withTimeout(.seconds(10)) {
          await events.first(where: { $0 == .postgresChangesReady })
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

        #expect(received.map(\.kind) == [.insert, .update, .delete])
        #expect(try received[0].row().key == testKey)
        #expect(try received[1].row().value.stringValue == "value2")
        #expect(received[2].oldRecord?["key"]?.stringValue == testKey)
        #expect(throws: RealtimeError.self) { try received[2].row() }
        #expect(
          received.allSatisfy { $0.raw.table == "key_value_storage" && $0.raw.errors.isEmpty })

        await channel.unsubscribe()
      }
    }

    @Test
    func postgresChangesWithFilter() async throws {
      let client = client
      try await withMainSerialExecutor {
        try await client.realtime.connect()

        let channel = await client.realtime.channel("postgres-filter")

        struct Entry: Codable, Equatable {
          let key: String
          let value: JSONValue
        }

        let testKey1 = UUID().uuidString
        let testKey2 = UUID().uuidString

        let filtered = await channel.postgresChanges(
          event: .insert,
          schema: "public",
          table: "key_value_storage",
          filter: .eq("key", value: testKey1)
        )
        let events = await channel.events()

        try await channel.subscribe()

        _ = try await withTimeout(.seconds(10)) {
          await events.first(where: { $0 == .postgresChangesReady })
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
        #expect(received[0].kind == .insert)
        let record = try #require(try received[0].record?.decode(as: Entry.self))
        #expect(record.key == testKey1)
        #expect(record.key != testKey2)

        await channel.unsubscribe()
      }
    }

    @Test
    func postgresChangesMultipleSubscriptions() async throws {
      let client = client
      try await withMainSerialExecutor {
        try await client.realtime.connect()

        let channel = await client.realtime.channel("postgres-multi")

        struct Entry: Codable, Equatable {
          let key: String
          let value: JSONValue
        }

        let insertions = await channel.postgresChanges(
          event: .insert, schema: "public", table: "key_value_storage")
        let updates = await channel.postgresChanges(
          event: .update, schema: "public", table: "key_value_storage")
        let deletions = await channel.postgresChanges(
          event: .delete, schema: "public", table: "key_value_storage")
        let events = await channel.events()

        try await channel.subscribe()

        _ = try await withTimeout(.seconds(10)) {
          await events.first(where: { $0 == .postgresChangesReady })
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

        #expect(inserted.map(\.kind) == [.insert])
        #expect(updated.map(\.kind) == [.update])
        #expect(deleted.map(\.kind) == [.delete])

        await channel.unsubscribe()
      }
    }

    //      try await client.realtime.connect()
    //      let channel = await client.realtime.channel("invalid-channel-test")
    //        try await channel.subscribe()
    //      let channel1 = await client.realtime.channel("broadcast-no-sub")
    //      let channel2 = await client2.realtime.channel("broadcast-no-sub")
    //        await channel2.broadcasts(event: "test").prefix(1).collect()
    //      try await channel2.subscribe()

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

        try await client.realtime.connect()
        try await client2.realtime.connect()

        let channel1 = await client.realtime.channel("app-room") {
          $0.broadcast.receiveOwnBroadcasts = true
        }

        let channel2 = await client2.realtime.channel("app-room") {
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

        let client1PresenceChanges = await channel1.presenceChanges()
        let client2PresenceChanges = await channel2.presenceChanges()

        let client1Messages = await channel1.broadcasts(event: "chat-message")
        let client2Messages = await channel2.broadcasts(event: "chat-message")

        try await channel1.subscribe()
        try await channel2.subscribe()

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

        try await channel1.untrack()
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

        let receivedMessage1 = try messages1[0].decode(as: ChatMessage.self)
        #expect(receivedMessage1.text == "Hello, Bob! How are you?")
        #expect(receivedMessage1.username == "Alice")

        let receivedMessage2 = try messages2[0].decode(as: ChatMessage.self)
        #expect(receivedMessage2.text == "Hello, Bob! How are you?")
        #expect(receivedMessage2.username == "Alice")

        let receivedMessage3 = try messages1[2].decode(as: ChatMessage.self)
        #expect(receivedMessage3.text == "Great to hear! Let's work on the project together.")
        #expect(receivedMessage3.username == "Alice")

        #expect(presenceChanges2.count > 0, "Client 2 should receive presence changes")

        await channel1.unsubscribe()
        await channel2.unsubscribe()
      }
    }

    @Test
    func presenceTrackUpdateAndUntrackReachTheOtherClient() async throws {
      let client = client
      let client2 = client2
      try await withMainSerialExecutor {
        struct Status: Codable, Equatable, Sendable {
          let name: String
          let status: String
        }

        try await client.realtime.connect()
        try await client2.realtime.connect()

        let topic = "presence-\(UUID().uuidString)"
        let ana = await client.realtime.channel(topic) { $0.presence.key = "ana" }
        let bob = await client2.realtime.channel(topic) { $0.presence.key = "bob" }
        let anaStates = await ana.presenceStates()
        let bobChanges = await bob.presenceChanges()
        try await ana.subscribe()
        try await bob.subscribe()

        try await ana.track(Status(name: "Ana", status: "online"))
        try await waitForPresence(on: bob) {
          try $0.decode(as: Status.self)["ana"] == [Status(name: "Ana", status: "online")]
        }

        try await ana.track(Status(name: "Ana", status: "away"))
        try await waitForPresence(on: bob) {
          try $0.decode(as: Status.self)["ana"] == [Status(name: "Ana", status: "away")]
        }

        try await ana.untrack()
        try await waitForPresence(on: bob) { $0.entries["ana"] == nil }

        let changes = try await withTimeout(.seconds(5)) {
          await bobChanges.filter { $0.joins["ana"] != nil || $0.leaves["ana"] != nil }
            .prefix(3).collect()
        }
        let joined = try #require(changes.first?.joins["ana"]?.first)
        let updated = try #require(changes.dropFirst().first)
        #expect(updated.joins["ana"]?.first?.previousRef == joined.ref)
        #expect(updated.leaves["ana"]?.map(\.ref) == [joined.ref])
        #expect(changes.last?.leaves["ana"]?.count == 1)

        await ana.unsubscribe()
        await bob.unsubscribe()
        withExtendedLifetime(anaStates) {}
      }
    }

    @Test
    func presenceTrackBeforeSubscribeThrowsNotSubscribed() async {
      let client = client
      await withMainSerialExecutor {
        let channel = await client.realtime.channel("presence-\(UUID().uuidString)")

        let error = await #expect(throws: RealtimeError.self) {
          try await channel.track(["name": "ana"] as JSONObject)
        }
        #expect(error?.kind == .notSubscribed)
      }
    }

    /// Polls the channel's presence state until `condition` holds, for at most five seconds.
    private func waitForPresence(
      on channel: RealtimeChannel,
      until condition: @escaping @Sendable (PresenceState) throws -> Bool
    ) async throws {
      try await withTimeout(.seconds(5)) {
        while try !condition(await channel.presenceState) {
          try await Task.sleep(for: .milliseconds(50))
        }
      }
    }

    private func subscribeMany(_ channels: [RealtimeChannel]) async throws {
      try await withThrowingTaskGroup { group in
        for channel in channels {
          group.addTask { try await channel.subscribe() }
        }

        try await group.waitForAll()
      }
    }

    private func unsubscribeMany(_ channels: [RealtimeChannel]) async {
      await withTaskGroup { group in
        for channel in channels {
          group.addTask { await channel.unsubscribe() }
        }

        await group.waitForAll()
      }
    }
  }
#endif
