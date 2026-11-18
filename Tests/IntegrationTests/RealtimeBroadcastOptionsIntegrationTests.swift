//
//  RealtimeBroadcastOptionsIntegrationTests.swift
//
//
//  Created by Guilherme Souza on 16/11/26.
//
// Linux: the official Swift images' libcurl is built without WebSocket support. See
// RealtimeIntegrationTests.
#if !os(Android) && !os(Linux)
  import Clocks
  import ConcurrencyExtras
  import Crypto
  import Foundation
  import PostgREST
  import TestHelpers
  import Testing

  @testable import Helpers
  @_spi(Testing) @testable import Realtime

  /// Broadcast join options and binary REST sends, against the local stack.
  ///
  /// The private-channel tests rely on the policies in
  /// `20261116000001_realtime_private_channels.sql`: the `authenticated` role can read every
  /// `swift-private:` topic and write all but the `swift-private:read-only:` ones.
  @Suite(
    .serialized,
    .timeLimit(.minutes(1)),
    .enabled(if: ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil)
  )
  struct RealtimeBroadcastOptionsIntegrationTests {
    let personal = try! PostgrestClient(
      configuration: .init(
        url: URL(string: "\(DotEnv.supabaseURL)/rest/v1")!,
        schema: "personal",
        headers: [.apikey: DotEnv.supabasePublishableKey]
      )
    )

    // MARK: - Replay

    /// A message the database stored on a private topic comes back, marked replayed, to a channel
    /// that joins later with a replay window.
    @Test
    func replayDeliversStoredMessagesToALaterJoin() async throws {
      let topic = "swift-private:replay-\(UUID().uuidString)"
      let since = Date().addingTimeInterval(-5)
      try await personal.from("notes").insert(["body": topic]).execute()

      let realtime = try makeClient(role: "authenticated")
      try await realtime.connect()
      let channel = await realtime.channel(topic) {
        $0.isPrivate = true
        $0.broadcast.replay = .init(since: since, limit: 10)
      }
      let messages = await channel.broadcasts(event: "note_inserted")
      try await channel.subscribe()

      let received = try? await withTimeout(.seconds(10)) {
        await messages.first(where: { _ in true })
      }
      await realtime.removeAllChannels()
      try await personal.from("notes").delete().eq("body", value: topic).execute()

      let message = try #require(received)
      #expect(message.isReplayed)
      #expect(try message.decode(as: [String: String].self)["body"] == topic)
    }

    /// Without a replay window the same join receives nothing from history.
    @Test
    func aJoinWithoutReplayReceivesNoStoredMessage() async throws {
      let topic = "swift-private:no-replay-\(UUID().uuidString)"
      try await personal.from("notes").insert(["body": topic]).execute()

      let realtime = try makeClient(role: "authenticated")
      try await realtime.connect()
      let channel = await realtime.channel(topic) { $0.isPrivate = true }
      let messages = await channel.broadcasts(event: "note_inserted")
      try await channel.subscribe()

      let received = try? await withTimeout(.seconds(2)) {
        await messages.first(where: { _ in true })
      }
      await realtime.removeAllChannels()
      try await personal.from("notes").delete().eq("body", value: topic).execute()

      #expect(received == nil)
    }

    // MARK: - Acknowledgements

    /// With acknowledgements on, `broadcast` returns once the server accepted the message, and a
    /// subscriber receives it.
    @Test
    func anAcknowledgedBroadcastReachesASubscriber() async throws {
      let topic = "ack-\(UUID().uuidString)"
      let receiver = try makeClient(role: "anon")
      let sender = try makeClient(role: "anon")
      try await receiver.connect()
      try await sender.connect()

      let listening = await receiver.channel(topic)
      let messages = await listening.broadcasts(event: "ping")
      try await listening.subscribe()

      let sending = await sender.channel(topic) { $0.broadcast.acknowledgesMessages = true }
      try await sending.subscribe()
      try await sending.broadcast(event: "ping", payload: ["n": 1] as JSONObject)

      let received = try? await withTimeout(.seconds(5)) {
        await messages.first(where: { _ in true })
      }
      await receiver.removeAllChannels()
      await sender.removeAllChannels()

      #expect(try received?.decode(as: [String: Int].self) == ["n": 1])
    }

    /// On a private topic the user may read but not write, the server refuses the broadcast, and
    /// with acknowledgements on `broadcast` throws its error. Without them the same call returns
    /// at once and the refusal goes unseen.
    @Test
    func anAcknowledgedBroadcastThatTheServerDeniesThrows() async throws {
      let topic = "swift-private:read-only:ack-\(UUID().uuidString)"
      let realtime = try makeClient(role: "authenticated")
      try await realtime.connect()

      let unacknowledged = await realtime.channel(topic) { $0.isPrivate = true }
      try await unacknowledged.subscribe()
      try await unacknowledged.broadcast(event: "ping", payload: ["n": 1] as JSONObject)
      await realtime.removeChannel(unacknowledged)

      let acknowledged = await realtime.channel(topic) {
        $0.isPrivate = true
        $0.broadcast.acknowledgesMessages = true
      }
      try await acknowledged.subscribe()
      let error = await #expect(throws: RealtimeError.self) {
        try await acknowledged.broadcast(event: "ping", payload: ["n": 2] as JSONObject)
      }
      await realtime.removeAllChannels()

      #expect(error?.kind == .server)
    }

    // MARK: - Replication

    /// A channel that waits for replication receives `replicationReady` from the server.
    @Test
    func waitsForReplicationEmitsReplicationReady() async throws {
      let realtime = try makeClient(role: "anon")
      try await realtime.connect()
      let channel = await realtime.channel("replication-\(UUID().uuidString)") {
        $0.broadcast.waitsForReplication = true
      }
      let events = await channel.events()
      try await channel.subscribe()

      let event = try? await withTimeout(.seconds(10)) {
        await events.first(where: {
          switch $0 {
          case .replicationReady, .replicationFailed: true
          default: false
          }
        })
      }
      await realtime.removeAllChannels()

      #expect(event == .replicationReady)
    }

    // MARK: - Postgres changes column subset

    /// `select` limits the change record to the listed columns. The server always adds the
    /// primary key, so selecting `id` alone leaves `body` out of the record.
    @Test
    func postgresChangesSelectLimitsTheRecordToTheListedColumns() async throws {
      let body = "select-\(UUID().uuidString)"
      let realtime = try makeClient(role: "anon")
      try await realtime.connect()
      let channel = await realtime.channel("postgres-select-\(UUID().uuidString)")
      let changes = await channel.postgresChanges(
        event: .insert, schema: "personal", table: "notes", filter: .eq("body", value: body),
        select: ["id"])
      let events = await channel.events()
      try await channel.subscribe()
      _ = try await withTimeout(.seconds(10)) {
        await events.first(where: { $0 == .postgresChangesReady })
      }

      try await personal.from("notes").insert(["body": body]).execute()

      let change = try? await withTimeout(.seconds(10)) {
        await changes.first(where: { _ in true })
      }
      await realtime.removeAllChannels()
      try await personal.from("notes").delete().eq("body", value: body).execute()

      let record = try #require(change?.record)
      #expect(record.values.keys.sorted() == ["id"])
    }

    // MARK: - Binary REST broadcast

    /// `httpSend(event:data:)` posts the bytes as `application/octet-stream`, and a subscriber
    /// receives them as a binary payload.
    @Test
    func binaryHTTPSendArrivesAsABinaryPayload() async throws {
      let topic = "http-send-binary-\(UUID().uuidString)"
      let receiver = try makeClient(role: "anon")
      let sender = try makeClient(role: "anon")
      try await receiver.connect()

      let listening = await receiver.channel(topic)
      let messages = await listening.broadcasts(event: "bytes")
      try await listening.subscribe()

      let bytes = Data([0x00, 0x01, 0xCA, 0xFE, 0xFF])
      try await sender.channel(topic).httpSend(event: "bytes", data: bytes)

      let received = try? await withTimeout(.seconds(5)) {
        await messages.first(where: { _ in true })
      }
      await receiver.removeAllChannels()
      await sender.removeAllChannels()

      #expect(received?.event == "bytes")
      #expect(received?.payload == .binary(bytes))
    }

    // MARK: - No signed-in user

    /// SWIFT-V3-004: an `accessToken` callback that returns `nil` after a user's token signs the
    /// user out. The joined private channel gets the API key, so the server closes it, and a new
    /// private join carries no token, so the server checks the API key's role and refuses it.
    @Test
    func aNilTokenRevokesTheSignedOutUsersPrivateChannels() async throws {
      let clock = TestClock<Duration>()
      let userToken = signedToken(role: "authenticated")
      let signedIn = LockIsolated(true)
      var configuration = RealtimeClient.Configuration(
        url: URL(string: DotEnv.supabaseURL)!.appendingPathComponent("realtime/v1"),
        headers: [.apikey: DotEnv.supabasePublishableKey],
        observesAppLifecycle: false,
        accessToken: { signedIn.value ? userToken : nil }
      )
      configuration.clock = clock
      let realtime = try RealtimeClient(configuration: configuration)
      try await realtime.connect()
      let joined = await realtime.channel("swift-private:revoked-\(UUID().uuidString)") {
        $0.isPrivate = true
      }
      try await joined.subscribe()

      signedIn.setValue(false)
      await clock.advance(by: RealtimeClient.accessTokenRefreshInterval)
      await realtime.setAuth()
      let closed = await waitUntil { await joined.status != .subscribed }

      let later = await realtime.channel("swift-private:after-\(UUID().uuidString)") {
        $0.isPrivate = true
      }
      let error = await #expect(throws: RealtimeError.self) { try await later.subscribe() }
      await realtime.removeAllChannels()

      #expect(await realtime.accessToken == nil)
      #expect(closed)
      #expect(error?.kind == .unauthorized)
    }

    // MARK: - Helpers

    private func makeClient(role: String) throws -> RealtimeClient {
      let token = signedToken(role: role)
      return try RealtimeClient(
        configuration: RealtimeClient.Configuration(
          url: URL(string: DotEnv.supabaseURL)!.appendingPathComponent("realtime/v1"),
          headers: [.apikey: DotEnv.supabasePublishableKey],
          observesAppLifecycle: false,
          accessToken: { token }
        )
      )
    }

    /// A token for `role` that the local stack accepts, signed with its JWT secret.
    private func signedToken(role: String) -> String {
      let header = Base64URL.encode(Data(#"{"alg":"HS256","typ":"JWT"}"#.utf8))
      let claims: [String: Any] = [
        "iss": "supabase-demo", "role": role, "sub": UUID().uuidString,
        "exp": Int(Date().timeIntervalSince1970 + 3600),
      ]
      let payload = Base64URL.encode(try! JSONSerialization.data(withJSONObject: claims))
      let signingInput = Data("\(header).\(payload)".utf8)
      let signature = HMAC<SHA256>.authenticationCode(
        for: signingInput, using: SymmetricKey(data: Data(DotEnv.jwtSecret.utf8)))
      return "\(header).\(payload).\(Base64URL.encode(Data(signature)))"
    }
  }
#endif
