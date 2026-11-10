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
  import Crypto
  import CustomDump
  import Foundation
  import Logging
  import OSLog
  @_spi(Experimental) import Supabase
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
      client = try SupabaseClient(
        supabaseURL: URL(string: DotEnv.supabaseURL) ?? URL(string: "http://127.0.0.1:54321")!,
        supabaseKey: DotEnv.supabasePublishableKey,
        configuration: SupabaseClient.Configuration(
          auth: .init(storage: InMemoryTestStorage()),
          global: .init(
            logger: Logging.Logger(label: "client1") {
              OSLogHandler(label: $0, subsystem: "realtime.integration.tests")
            },
            clock: testClock
          )
        )
      )
      client2 = try SupabaseClient(
        supabaseURL: URL(string: DotEnv.supabaseURL) ?? URL(string: "http://127.0.0.1:54321")!,
        supabaseKey: DotEnv.supabasePublishableKey,
        configuration: SupabaseClient.Configuration(
          auth: .init(storage: InMemoryTestStorage()),
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

        // A removed handle reads `.unsubscribed`; its actions throw `channelRemoved`.
        #expect(await channel.status == .unsubscribed)
        let error = await #expect(throws: RealtimeError.self) { try await channel.subscribe() }
        #expect(error?.kind == .channelRemoved)
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

        // A removed handle reads `.unsubscribed`; its actions throw `channelRemoved`.
        for channel in [channel1, channel2, channel3] {
          #expect(await channel.status == .unsubscribed)
          let error = await #expect(throws: RealtimeError.self) { try await channel.subscribe() }
          #expect(error?.kind == .channelRemoved)
        }
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
          $0.broadcast.receiveOwnMessages = true
        }

        struct Message: Codable, Sendable {
          let value: Int
          let text: String
        }

        let receivedMessagesStream = await channel.broadcasts(event: "test-event")

        try await channel.subscribe()

        try await channel.broadcast(event: "test-event", payload: Message(value: 1, text: "first"))
        try await channel.broadcast(
          event: "test-event", payload: Message(value: 2, text: "second"))
        try await channel.broadcast(
          event: "test-event", payload: ["value": 3, "text": "third"] as JSONObject)

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
    func heartbeatsNeverReplayAnEarlierEvent() async throws {
      // A heartbeat goes out only when the test advances `clock`, so no heartbeat can start
      // while `late` registers.
      let clock = TestClock<Duration>()
      let realtime = try RealtimeClient(
        configuration: RealtimeClient.Configuration(
          url: URL(string: DotEnv.supabaseURL)!.appendingPathComponent("realtime/v1"),
          headers: [
            .apikey: DotEnv.supabasePublishableKey,
            .authorization: "Bearer \(DotEnv.supabasePublishableKey)",
          ],
          heartbeatInterval: .seconds(1),
          disconnectOnEmptyChannelsAfter: .seconds(3600),
          observesAppLifecycle: false,
          clock: clock
        )
      )
      try await realtime.connect()

      // Collect first and assert after `disconnect()`, so a failure cannot leave the socket open.
      let early = await realtime.heartbeats()
      await clock.advance(by: .seconds(1))
      let firstCycle = try? await withTimeout(.seconds(5)) { await early.prefix(2).collect() }

      let late = await realtime.heartbeats()
      await clock.advance(by: .seconds(1))
      let next = try? await withTimeout(.seconds(5)) { await late.first { _ in true } }
      await realtime.disconnect()

      #expect(firstCycle == [.sent, .acknowledged(latency: .zero)])
      #expect(next == .sent, "a new stream starts with the next heartbeat, not the last ack")
    }

    @Test
    func customOptionsConnectSubscribeAndReceive() async throws {
      let realtime = try RealtimeClient(
        configuration: RealtimeClient.Configuration(
          url: URL(string: DotEnv.supabaseURL)!.appendingPathComponent("realtime/v1"),
          headers: [
            .apikey: DotEnv.supabasePublishableKey,
            .authorization: "Bearer \(DotEnv.supabasePublishableKey)",
          ],
          requestTimeout: .seconds(10),
          observesAppLifecycle: false,
          serverLogLevel: .warning,
          webSocketTransport: URLSessionWebSocketTransport(configuration: .ephemeral)
        )
      )
      try await withMainSerialExecutor {
        try await realtime.connect()

        let channel = await realtime.channel("custom-options-\(UUID().uuidString)") {
          $0.broadcast.receiveOwnMessages = true
        }
        let received = await channel.broadcasts(event: "ping")
        try await channel.subscribe()

        try await channel.broadcast(event: "ping", payload: ["value": 1] as JSONObject)

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
          $0.broadcast.receiveOwnMessages = true
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
          $0.broadcast.receiveOwnMessages = true
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

        try await channel.broadcast(event: "after-token", payload: ["value": 1] as JSONObject)
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
          $0.broadcast.receiveOwnMessages = true
        }

        let event1Messages = await channel.broadcasts(event: "event-1")
        let event2Messages = await channel.broadcasts(event: "event-2")

        try await channel.subscribe()

        try await channel.broadcast(event: "event-1", payload: ["data": "1"])
        try await channel.broadcast(event: "event-2", payload: ["data": "2"])
        try await channel.broadcast(event: "event-1", payload: ["data": "3"])
        try await channel.broadcast(event: "event-2", payload: ["data": "4"])

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
          $0.broadcast.receiveOwnMessages = false
        }

        let receivedCount = LockIsolated<Int>(0)
        let broadcasts = await channel.broadcasts(event: "test")
        let subscription = Task {
          for await _ in broadcasts {
            receivedCount.withValue { $0 += 1 }
          }
        }

        try await channel.subscribe()

        try await channel.broadcast(event: "test", payload: ["data": "test"])

        try await Task.sleep(nanoseconds: 500_000_000)

        #expect(receivedCount.value == 0)

        subscription.cancel()
        await channel.unsubscribe()
      }
    }

    /// A database trigger sends the message with `realtime.send`, not a client. See
    /// `20261105000000_realtime_trigger_broadcast.sql`. The row it inserts and deletes reaches
    /// every Postgres changes stream on `key_value_storage` that joins right after, so no such
    /// test may follow this one closely.
    @Test
    func aMessageTheDatabaseBroadcastsFromATriggerArrives() async throws {
      let client = client
      let key = "trigger-broadcast:\(UUID().uuidString)"
      try await withMainSerialExecutor {
        try await client.realtime.connect()

        let channel = await client.realtime.channel(key)
        let messages = await channel.broadcasts(event: "row_inserted")
        try await channel.subscribe()

        _ = try await client.from("key_value_storage")
          .insert(["key": key, "value": "from the trigger"]).execute()

        let received = try await withTimeout(.seconds(10)) {
          await messages.first(where: { _ in true })
        }

        #expect(received?.event == "row_inserted")
        // `realtime.send` adds the message's `id` to the payload.
        guard case .json(let payload)? = received?.payload else {
          Issue.record("Expected a JSON payload, got \(String(describing: received?.payload))")
          return
        }
        #expect(payload.objectValue?["key"] == .string(key))
        #expect(payload.objectValue?["value"] == .string("from the trigger"))

        await channel.unsubscribe()
        _ = try await client.from("key_value_storage").delete().eq("key", value: key).execute()
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
        #expect(error?.code == .unauthorized)
        #expect(error?.isRetryable == false)
        #expect(await channel.status == .failed)
        #expect(await channel.status.error?.code == .unauthorized)
      }
    }

    /// The server refuses a Postgres changes binding on a table that does not exist. The join
    /// is still in flight when it does, so `subscribe()` throws and the channel ends `failed`;
    /// `events()` carries the server's message.
    @Test
    func aPostgresChangesBindingTheServerRefusesFailsTheSubscribe() async throws {
      let client = client
      try await withMainSerialExecutor {
        try await client.realtime.connect()

        let channel = await client.realtime.channel("postgres-refused-binding")
        // Dropping the stream removes the binding, so it must outlive the subscribe.
        let changes = await channel.postgresChanges(
          event: .insert, schema: "public", table: "no_such_table")
        let events = await channel.events()

        let error = await #expect(throws: RealtimeError.self) { try await channel.subscribe() }
        #expect(error?.kind == .server)
        #expect(error?.isRetryable == false)
        #expect(await channel.status == .failed)

        let event = try await withTimeout(.seconds(5)) {
          await events.first(where: {
            if case .postgresChangesFailed = $0 { true } else { false }
          })
        }
        guard case .postgresChangesFailed(let reason)? = event else {
          Issue.record("Expected postgresChangesFailed, got \(String(describing: event))")
          return
        }
        #expect(reason.contains("no_such_table"))
        withExtendedLifetime(changes) {}
      }
    }

    /// The server refuses a join whose token expired. The client fetches the token again, once,
    /// and joins with the new one. `testClock` never advances, so no timer drives the refresh.
    @Test
    func anExpiredTokenOnJoinRefreshesOnceAndRejoins() async throws {
      let expired = signedToken(expiringIn: -60)
      let fresh = signedToken(expiringIn: 3600)
      let fetched = LockIsolated<[String]>([])
      let realtime = try makeRealtimeClient {
        fetched.withValue { tokens in
          let token = tokens.isEmpty ? expired : fresh
          tokens.append(token)
          return token
        }
      }
      try await withMainSerialExecutor {
        try await realtime.connect()

        let channel = await realtime.channel("token-expired-on-join")
        try await channel.subscribe()

        #expect(await channel.status == .subscribed)
        #expect(fetched.value == [expired, fresh])

        await realtime.removeAllChannels()
        await realtime.disconnect()
      }
    }

    /// The server closes a joined channel when its token expires, and the client does not join it
    /// again: the channel is spent, as after `removeChannel(_:)`.
    @Test
    func aTokenThatExpiresWhileJoinedClosesTheChannel() async throws {
      let token = signedToken(expiringIn: 5)
      let realtime = try makeRealtimeClient { token }
      try await withMainSerialExecutor {
        try await realtime.connect()

        let channel = await realtime.channel("token-expires-while-joined")
        try await channel.subscribe()
        #expect(await channel.status == .subscribed)

        // The stream starts at the current status, `.subscribed`.
        let statuses = await channel.statusChanges()
        _ = try await withTimeout(.seconds(20)) {
          await statuses.first(where: { $0 == .unsubscribed })
        }

        #expect(await channel.status == .unsubscribed)
        #expect(await realtime.channels.isEmpty)
        let error = await #expect(throws: RealtimeError.self) { try await channel.subscribe() }
        #expect(error?.kind == .channelRemoved)

        await realtime.disconnect()
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
    func postgresChangesForARelationWithATypedFilter() async throws {
      let client = client
      try await withMainSerialExecutor {
        try await client.realtime.connect()

        let channel = await client.realtime.channel("postgres-typed-relation")

        let matchedKey = UUID().uuidString
        let skippedKey = UUID().uuidString

        let changes = try await channel.postgresChanges(
          of: KeyValueStorage.self,
          event: .insert,
          where: { $0.key.eq(matchedKey) && !$0.key.eq(skippedKey) }
        )
        let events = await channel.events()

        try await channel.subscribe()

        _ = try await withTimeout(.seconds(10)) {
          await events.first(where: { $0 == .postgresChangesReady })
        }

        _ = try await client.from("key_value_storage")
          .insert(["key": skippedKey, "value": "skipped"]).execute()
        _ = try await client.from("key_value_storage")
          .insert(["key": matchedKey, "value": "matched"]).execute()

        let received = try await withTimeout(.seconds(5)) {
          await changes.prefix(1).collect()
        }

        #expect(received.map(\.kind) == [.insert])
        let row = try #require(try received.first?.row())
        #expect(row.key == matchedKey)
        #expect(row.value?.stringValue == "matched")

        await channel.unsubscribe()
      }
    }

    @Test
    func streamKeepsTheFilteredRowsInSync() async throws {
      let client = client
      let first = UUID().uuidString
      let second = UUID().uuidString
      let outside = UUID().uuidString
      _ = try await client.from("key_value_storage")
        .insert(["key": first, "value": "before"]).execute()

      let results = LockIsolated<[[KeyValueStorage]]>([])
      let iteration = Task {
        for try await rows in client.stream(
          of: KeyValueStorage.self, where: { $0.key.in([first, second]) })
        {
          results.withValue { $0.append(rows) }
        }
      }
      @Sendable func latest() -> [String: String?] {
        Dictionary(
          uniqueKeysWithValues: (results.value.last ?? []).map { ($0.key, $0.value?.stringValue) })
      }

      #expect(await waitUntil { latest() == [first: "before"] })

      _ = try await client.from("key_value_storage")
        .insert([["key": outside, "value": "outside"], ["key": second, "value": "added"]])
        .execute()
      #expect(await waitUntil { latest() == [first: "before", second: "added"] })

      _ = try await client.from("key_value_storage")
        .update(["value": "after"]).eq("key", value: first).execute()
      #expect(await waitUntil { latest() == [first: "after", second: "added"] })

      _ = try await client.from("key_value_storage").delete().eq("key", value: second).execute()
      #expect(await waitUntil { latest() == [first: "after"] })

      iteration.cancel()
      #expect(
        await waitUntil {
          await !client.realtime.channels.contains { $0.topic.hasPrefix("live:") }
        }
      )
      _ = try await client.from("key_value_storage")
        .delete().in("key", values: [first, outside]).execute()
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
          $0.broadcast.receiveOwnMessages = true
        }

        let channel2 = await client2.realtime.channel("app-room") {
          $0.broadcast.receiveOwnMessages = true
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
        try await channel1.broadcast(event: "chat-message", payload: message1)
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
        try await channel2.broadcast(event: "chat-message", payload: message2)
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
        try await channel1.broadcast(event: "chat-message", payload: message3)
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
    func aPresenceStreamOpenedAfterSubscribeWorksWithTheEnabledOption() async throws {
      let client = client
      let client2 = client2
      try await withMainSerialExecutor {
        try await client.realtime.connect()
        try await client2.realtime.connect()

        let topic = "presence-late-\(UUID().uuidString)"
        let ana = await client.realtime.channel(topic) { $0.presence.key = "ana" }
        let bob = await client2.realtime.channel(topic) {
          $0.presence.key = "bob"
          $0.presence.isEnabled = true
        }
        try await ana.subscribe()
        try await bob.subscribe()

        let bobChanges = await bob.presenceChanges()
        try await ana.track(["name": "Ana"] as JSONObject)

        let joined = try await withTimeout(.seconds(5)) {
          await bobChanges.first { $0.joins["ana"] != nil }
        }
        #expect(joined?.joins["ana"]?.first?.payload == ["name": "Ana"])

        await ana.unsubscribe()
        await bob.unsubscribe()
      }
    }

    @Test
    func aPresenceStreamOpenedAfterATrackSeesTheOtherClients() async throws {
      let client = client
      let client2 = client2
      try await withMainSerialExecutor {
        try await client.realtime.connect()
        try await client2.realtime.connect()

        let topic = "presence-late-track-\(UUID().uuidString)"
        let ana = await client.realtime.channel(topic) { $0.presence.key = "ana" }
        let bob = await client2.realtime.channel(topic) { $0.presence.key = "bob" }
        try await ana.subscribe()
        try await bob.subscribe()

        try await ana.track(["name": "Ana"] as JSONObject)
        try await waitForPresence(on: ana) { $0.entries["ana"] != nil }

        let anaStates = await ana.presenceStates()
        try await bob.track(["name": "Bob"] as JSONObject)

        let (first, withBob) = try await withTimeout(.seconds(5)) {
          () async -> (PresenceState?, PresenceState?) in
          var states = anaStates.makeAsyncIterator()
          let first = await states.next()
          while let state = await states.next() {
            if state.entries["bob"] != nil { return (first, state) }
          }
          return (first, nil)
        }
        #expect(first?.entries["ana"] != nil)
        #expect(withBob?.entries["bob"]?.first?.payload == ["name": "Bob"])

        await ana.unsubscribe()
        await bob.unsubscribe()
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
    /// `subscribe()` returns only once the server's Postgres changes are live, so a row
    /// inserted right after it arrives. With `waitForSubscription`, the server holds the join
    /// reply instead of the SDK waiting for "Subscribed to PostgreSQL".
    @Test(arguments: [false, true])
    func subscribeReturnsWhenPostgresChangesAreLive(waitForSubscription: Bool) async throws {
      let client = client
      try await withMainSerialExecutor {
        try await client.realtime.connect()

        let channel = await client.realtime.channel("postgres-live-\(waitForSubscription)") {
          $0.postgresChanges.waitForSubscription = waitForSubscription
        }
        let testKey = UUID().uuidString
        let inserts = await channel.postgresChanges(
          of: KeyValueEntry.self, event: .insert, table: "key_value_storage",
          filter: .eq("key", value: testKey))

        try await channel.subscribe()
        try await client.from("key_value_storage").insert(["key": testKey, "value": "v"]).execute()

        let change = try await withTimeout(.seconds(5)) {
          await inserts.first(where: { _ in true })
        }
        #expect(try change?.row().key == testKey)

        await channel.unsubscribe()
      }
    }

    /// A `postgresChanges` stream opened on a joined channel makes it rejoin with the binding.
    @Test
    func lateBindingRejoinsAndDelivers() async throws {
      let client = client
      try await withMainSerialExecutor {
        try await client.realtime.connect()

        let channel = await client.realtime.channel("late-binding")
        let pings = await channel.broadcasts(event: "ping")
        let events = await channel.events()
        try await channel.subscribe()

        let testKey = UUID().uuidString
        let inserts = await channel.postgresChanges(
          of: KeyValueEntry.self, event: .insert, table: "key_value_storage",
          filter: .eq("key", value: testKey))
        _ = try await withTimeout(.seconds(10)) {
          await events.first(where: { $0 == .resubscribed })
        }
        #expect(await channel.status == .subscribed)

        try await client.from("key_value_storage").insert(["key": testKey, "value": "v"]).execute()
        let change = try await withTimeout(.seconds(5)) {
          await inserts.first(where: { _ in true })
        }
        #expect(try change?.row().key == testKey)

        withExtendedLifetime(pings) {}
        await channel.unsubscribe()
      }
    }

    /// Broadcast events match exactly and by case; `"*"` matches every event.
    @Test
    func broadcastMatchingIsExact() async throws {
      let client = client
      try await withMainSerialExecutor {
        try await client.realtime.connect()

        let channel = await client.realtime.channel("broadcast-exact") {
          $0.broadcast.receiveOwnMessages = true
        }
        let lowercase = await channel.broadcasts(event: "ping")
        let exact = await channel.broadcasts(event: "Ping")
        let wildcard = await channel.broadcasts(event: "*")
        try await channel.subscribe()

        try await channel.broadcast(event: "Ping", payload: ["n": 1])
        try await channel.broadcast(event: "ping", payload: ["n": 2])

        let (exactMessage, wildcardMessages, lowercaseMessage) = try await withTimeout(
          .seconds(5)
        ) {
          (
            await exact.first(where: { _ in true }),
            await wildcard.prefix(2).collect(),
            await lowercase.first(where: { _ in true })
          )
        }
        #expect(try exactMessage?.decode(as: [String: Int].self) == ["n": 1])
        #expect(wildcardMessages.map(\.event) == ["Ping", "ping"])
        // "Ping" did not reach the "ping" stream: its first message is the second broadcast.
        #expect(try lowercaseMessage?.decode(as: [String: Int].self) == ["n": 2])

        await channel.unsubscribe()
      }
    }

    /// `topic` is the name passed to `channel(_:)`, and `httpSend` reaches a subscriber on it.
    @Test
    func channelTopicIsTheUserName() async throws {
      let client = client
      try await withMainSerialExecutor {
        try await client.realtime.connect()

        let channel = await client.realtime.channel("topic-name")
        #expect(channel.topic == "topic-name")
        let messages = await channel.broadcasts(event: "rest")
        try await channel.subscribe()

        try await channel.httpSend(event: "rest", payload: ["n": 1])

        let message = try await withTimeout(.seconds(5)) {
          await messages.first(where: { _ in true })
        }
        #expect(message?.event == "rest")
        #expect(try message?.decode(as: [String: Int].self) == ["n": 1])

        await channel.unsubscribe()
      }
    }

    /// `httpSend` sends the global headers and `X-Client-Info`, and the server accepts it.
    @Test
    func httpSendSendsTheConfiguredHeaders() async throws {
      let recorder = HeaderRecorder()
      let client = try SupabaseClient(
        supabaseURL: URL(string: DotEnv.supabaseURL) ?? URL(string: "http://127.0.0.1:54321")!,
        supabaseKey: DotEnv.supabasePublishableKey,
        configuration: SupabaseClient.Configuration(
          auth: .init(storage: InMemoryTestStorage()),
          global: .init(
            headers: [HTTPField.Name("X-Integration-Test")!: "httpSend"],
            http: .init(middlewares: [recorder]),
            clock: testClock
          )
        )
      )

      let channel = await client.realtime.channel("http-send-headers")
      try await channel.httpSend(event: "rest", payload: ["n": 1])

      let headers = try #require(recorder.headers.value.last)
      #expect(headers[HTTPField.Name("X-Integration-Test")!] == "httpSend")
      #expect(headers[.xClientInfo]?.hasPrefix("supabase-swift/") == true)
      #expect(headers[.apikey] == DotEnv.supabasePublishableKey)
      #expect(headers[.authorization] == "Bearer \(DotEnv.supabasePublishableKey)")
      #expect(headers[.contentType] == "application/json")
      #expect(recorder.headers.value.count == 1)

      await client.realtime.removeAllChannels()
    }

    /// Without an access token, `httpSend` sends only `apikey`, and a subscriber on the public
    /// channel receives the broadcast.
    @Test
    func httpSendWithoutAnAccessTokenReachesAPublicChannel() async throws {
      let client = client
      let sender = try makeRealtimeClient(accessToken: { nil })
      try await withMainSerialExecutor {
        try await client.realtime.connect()
        let receiver = await client.realtime.channel("http-send-no-token")
        let messages = await receiver.broadcasts(event: "rest")
        try await receiver.subscribe()

        let channel = await sender.channel("http-send-no-token")
        try await channel.httpSend(event: "rest", payload: ["n": 1])

        let message = try await withTimeout(.seconds(5)) {
          await messages.first(where: { _ in true })
        }
        #expect(try message?.decode(as: [String: Int].self) == ["n": 1])

        await receiver.unsubscribe()
        await sender.removeAllChannels()
      }
    }

    private struct HeaderRecorder: ClientMiddleware {
      let headers = LockIsolated<[HTTPFields]>([])

      func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        next:
          nonisolated(nonsending) @Sendable (HTTPRequest, HTTPBody?) async throws -> (
            HTTPResponse, HTTPBody?
          )
      ) async throws -> (HTTPResponse, HTTPBody?) {
        headers.withValue { $0.append(request.headerFields) }
        return try await next(request, body)
      }
    }

    private struct KeyValueEntry: Decodable {
      let key: String
    }

    /// A `RealtimeClient` on the local stack that joins with the token `accessToken` returns,
    /// on `testClock`.
    private func makeRealtimeClient(
      accessToken: @escaping @Sendable () async throws -> String?
    ) throws -> RealtimeClient {
      try RealtimeClient(
        configuration: RealtimeClient.Configuration(
          url: URL(string: DotEnv.supabaseURL)!.appendingPathComponent("realtime/v1"),
          headers: [.apikey: DotEnv.supabasePublishableKey],
          observesAppLifecycle: false,
          accessToken: accessToken,
          clock: testClock
        )
      )
    }

    /// An `anon` token the local stack accepts, signed with its JWT secret, that expires
    /// `seconds` from now. A negative value mints a token that has already expired.
    private func signedToken(expiringIn seconds: TimeInterval) -> String {
      let header = Base64URL.encode(Data(#"{"alg":"HS256","typ":"JWT"}"#.utf8))
      let claims: [String: Any] = [
        "iss": "supabase-demo", "role": "anon", "exp": Int(Date().timeIntervalSince1970 + seconds),
      ]
      let payload = Base64URL.encode(try! JSONSerialization.data(withJSONObject: claims))
      let signingInput = Data("\(header).\(payload)".utf8)
      let signature = HMAC<SHA256>.authenticationCode(
        for: signingInput, using: SymmetricKey(data: Data(DotEnv.jwtSecret.utf8)))
      return "\(header).\(payload).\(Base64URL.encode(Data(signature)))"
    }

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
