import Clocks
import ConcurrencyExtras
import CustomDump
import Foundation
import InlineSnapshotTesting
import TestHelpers
import Testing
@testable import Realtime
#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

#if os(Linux)
#else

  /// Appends every element of `stream` to the returned box until the returned task is cancelled.
  private func collect<Element: Sendable>(
    _ stream: AsyncStream<Element>
  ) -> (values: LockIsolated<[Element]>, task: Task<Void, Never>) {
    let values = LockIsolated<[Element]>([])
    let task = Task {
      for await element in stream {
        values.withValue { $0.append(element) }
      }
    }
    return (values, task)
  }

  @Suite(.serialized, .mainSerialExecutorSerialized)
  final class RealtimeTests: Sendable {
    let url = URL(string: "http://localhost:54321/realtime/v1")!
    let apiKey = "publishable.api.key"

    let server: FakeWebSocket
    let client: FakeWebSocket
    let http: RecordingTransport
    let sut: RealtimeClient
    let testClock: SignalingTestClock

    let heartbeatInterval = RealtimeClientOptions.defaultHeartbeatInterval
    let reconnectDelay = RealtimeClientOptions.defaultReconnectDelay
    let timeout = RealtimeClientOptions.defaultTimeout

    init() {
      let (client, server) = FakeWebSocket.fakes()
      self.client = client
      self.server = server
      http = RecordingTransport()
      testClock = SignalingTestClock()

      sut = RealtimeClient(
        url: url,
        options: RealtimeClientOptions(
          headers: ["apikey": apiKey],
          accessToken: {
            "custom.access.token"
          }
        ),
        wsTransport: { _, _ in client },
        http: HTTPClient(transport: http),
        clock: testClock
      )
    }

    @Test
    func transport() async throws {
      try await withMainSerialExecutor {
        let client = RealtimeClient(
          url: url,
          options: RealtimeClientOptions(
            headers: ["apikey": apiKey],
            logLevel: .warn,
            accessToken: {
              "custom.access.token"
            }
          ),
          wsTransport: { url, _ in
            assertInlineSnapshot(of: url, as: .description) {
              """
              ws://localhost:54321/realtime/v1/websocket?apikey=publishable.api.key&vsn=2.0.0&log_level=warn
              """
            }
            return FakeWebSocket.fakes().0
          },
          http: HTTPClient(transport: http),
          clock: testClock
        )

        try await client.connect()
      }
    }

    @Test
    func behavior() async throws {
      try await withMainSerialExecutor {
        let channel = await sut.channel("public:messages")

        let inserts = await channel.postgresChanges(InsertAction.self, table: "messages")
        let updates = await channel.postgresChanges(UpdateAction.self, table: "messages")
        let deletes = await channel.postgresChanges(DeleteAction.self, table: "messages")

        let socketStatuses = collect(sut.statusChanges)
        defer { socketStatuses.task.cancel() }

        let serverTask = Task { @Sendable [server = server] in
          for await event in server.events {
            guard let msg = event.realtimeMessage else { continue }
            if msg.event == "heartbeat" {
              server.send(
                RealtimeMessageV2(
                  joinRef: msg.joinRef,
                  ref: msg.ref,
                  topic: "phoenix",
                  event: "phx_reply",
                  payload: ["response": [:]]
                )
              )
            } else if msg.event == "phx_join" {
              server.send(.messagesSubscribed)
            }
          }
        }
        defer { serverTask.cancel() }

        let channelStatuses = collect(channel.statusChanges)
        defer { channelStatuses.task.cancel() }

        do {
          try await channel.subscribe()
        } catch {
          Issue.record("Expected .subscribed but got error: \(error)")
        }
        // The postgres streams shape the join payload; keep them open until the join went out.
        withExtendedLifetime((inserts, updates, deletes)) {}

        await waitUntil { channelStatuses.values.value.count >= 3 }
        #expect(channelStatuses.values.value == [.unsubscribed, .subscribing, .subscribed])

        await waitUntil { socketStatuses.values.value.count >= 3 }
        #expect(
          Array(socketStatuses.values.value.prefix(3))
            == [.disconnected, .connecting, .connected]
        )

        let messageTask = await sut.messageTask
        #expect(messageTask != nil)

        let heartbeatTask = await sut.heartbeatTask
        #expect(heartbeatTask != nil)

        assertInlineSnapshot(of: client.sentEvents.map(\.json), as: .json) {
          #"""
          [
            {
              "text" : [
                "1",
                "1",
                "realtime:public:messages",
                "phx_join",
                {
                  "access_token" : "custom.access.token",
                  "config" : {
                    "broadcast" : {
                      "ack" : false,
                      "replication_ready" : false,
                      "self" : false
                    },
                    "postgres_changes" : [
                      {
                        "event" : "INSERT",
                        "schema" : "public",
                        "table" : "messages"
                      },
                      {
                        "event" : "UPDATE",
                        "schema" : "public",
                        "table" : "messages"
                      },
                      {
                        "event" : "DELETE",
                        "schema" : "public",
                        "table" : "messages"
                      }
                    ],
                    "presence" : {
                      "enabled" : false,
                      "key" : ""
                    },
                    "private" : false
                  },
                  "version" : "realtime-swift\/0.0.0"
                }
              ]
            }
          ]
          """#
        }
      }
    }

    @Test(.requiresMainSerialExecutor)
    func subscribeTimeout() async throws {
      try await withMainSerialExecutor {
        let channel = await sut.channel("public:messages")
        let joinEventCount = LockIsolated(0)

        let serverTask = Task { @Sendable [server = server] in
          for await event in server.events {
            guard let msg = event.realtimeMessage else { continue }
            if msg.event == "heartbeat" {
              server.send(
                RealtimeMessageV2(
                  joinRef: msg.joinRef,
                  ref: msg.ref,
                  topic: "phoenix",
                  event: "phx_reply",
                  payload: ["response": [:]]
                )
              )
            } else if msg.event == "phx_join" {
              joinEventCount.withValue { $0 += 1 }
              if joinEventCount.value == 2 {
                server.send(.messagesSubscribed)
              }
            }
          }
        }
        defer { serverTask.cancel() }

        try await sut.connect()
        await testClock.advance(by: heartbeatInterval)

        Task {
          try await channel.subscribe()
        }

        await testClock.advance(by: timeout)

        await testClock.advance(by: .seconds(2.5))

        // The heartbeat and the joins share one ref counter on `RealtimeClient`, so the
        // heartbeat sent above takes ref "1" and the two joins take "2" and "3".
        let events: [JSONObject] = client.sentEvents.compactMap { $0.realtimeMessage }
          .filter { $0.event == "phx_join" }
          .map {
            [
              "event": .string($0.event),
              "join_ref": $0.joinRef.map(JSONValue.string) ?? .null,
              "payload": .object($0.payload),
              "ref": $0.ref.map(JSONValue.string) ?? .null,
              "topic": .string($0.topic),
            ]
          }
        assertInlineSnapshot(of: events, as: .json) {
          #"""
          [
            {
              "event" : "phx_join",
              "join_ref" : "2",
              "payload" : {
                "access_token" : "custom.access.token",
                "config" : {
                  "broadcast" : {
                    "ack" : false,
                    "replication_ready" : false,
                    "self" : false
                  },
                  "postgres_changes" : [

                  ],
                  "presence" : {
                    "enabled" : false,
                    "key" : ""
                  },
                  "private" : false
                },
                "version" : "realtime-swift\/0.0.0"
              },
              "ref" : "2",
              "topic" : "realtime:public:messages"
            },
            {
              "event" : "phx_join",
              "join_ref" : "3",
              "payload" : {
                "access_token" : "custom.access.token",
                "config" : {
                  "broadcast" : {
                    "ack" : false,
                    "replication_ready" : false,
                    "self" : false
                  },
                  "postgres_changes" : [

                  ],
                  "presence" : {
                    "enabled" : false,
                    "key" : ""
                  },
                  "private" : false
                },
                "version" : "realtime-swift\/0.0.0"
              },
              "ref" : "3",
              "topic" : "realtime:public:messages"
            }
          ]
          """#
        }
      }
    }

    @Test(.requiresMainSerialExecutor)
    func subscribeTimeout_successAfterRetries() async throws {
      try await withMainSerialExecutor {
        let successAttempt = 3
        let channel = await sut.channel("public:messages")
        let joinEventCount = LockIsolated(0)

        let serverTask = Task { @Sendable [server = server] in
          for await event in server.events {
            guard let msg = event.realtimeMessage else { continue }
            if msg.event == "heartbeat" {
              server.send(
                RealtimeMessageV2(
                  joinRef: msg.joinRef,
                  ref: msg.ref,
                  topic: "phoenix",
                  event: "phx_reply",
                  payload: ["response": [:]]
                )
              )
            } else if msg.event == "phx_join" {
              joinEventCount.withValue { $0 += 1 }
              if joinEventCount.value == successAttempt {
                server.send(.messagesSubscribed)
              }
            }
          }
        }
        defer { serverTask.cancel() }

        try await sut.connect()
        await testClock.advance(by: heartbeatInterval)

        let subscribeTask = Task {
          _ = try? await channel.subscribe()
        }

        for attempt in 1..<successAttempt {
          await testClock.advance(by: timeout)
          let retryDelay = pow(2.0, Double(attempt))
          await testClock.advance(by: .seconds(retryDelay))
        }

        await subscribeTask.value

        let events = client.sentEvents.compactMap { $0.realtimeMessage }.filter {
          $0.event == "phx_join"
        }

        #expect(events.count == successAttempt)
        #expect(await channel.status == .subscribed)
      }
    }

    @Test(.requiresMainSerialExecutor)
    func subscribeTimeout_failsAfterMaxRetries() async throws {
      try await withMainSerialExecutor {
        let channel = await sut.channel("public:messages")
        let joinEventCount = LockIsolated(0)

        let serverTask = Task { @Sendable [server = server] in
          for await event in server.events {
            guard let msg = event.realtimeMessage else { continue }
            if msg.event == "heartbeat" {
              server.send(
                RealtimeMessageV2(
                  joinRef: msg.joinRef,
                  ref: msg.ref,
                  topic: "phoenix",
                  event: "phx_reply",
                  payload: ["response": [:]]
                )
              )
            } else if msg.event == "phx_join" {
              joinEventCount.withValue { $0 += 1 }
            }
          }
        }
        defer { serverTask.cancel() }

        try await sut.connect()
        await testClock.advance(by: heartbeatInterval)

        let subscribeTask = Task {
          try await channel.subscribe()
        }

        for attempt in 1...5 {
          await testClock.advance(by: timeout)
          if attempt < 5 {
            let retryDelay = 2.5 * Double(attempt)
            await testClock.advance(by: .seconds(retryDelay))
          }
        }

        do {
          try await subscribeTask.value
          Issue.record("Expected error but got success")
        } catch {
          #expect(error is RealtimeError)
        }

        let events = client.sentEvents.compactMap { $0.realtimeMessage }.filter {
          $0.event == "phx_join"
        }
        #expect(events.count == 5)
        #expect(await channel.status == .unsubscribed)
      }
    }

    @Test
    func subscribeTimeout_cancelsOnTaskCancel() async throws {
      try await withMainSerialExecutor {
        let channel = await sut.channel("public:messages")
        let joinEventCount = LockIsolated(0)

        let serverTask = Task { @Sendable [server = server] in
          for await event in server.events {
            guard let msg = event.realtimeMessage else { continue }
            if msg.event == "heartbeat" {
              server.send(
                RealtimeMessageV2(
                  joinRef: msg.joinRef,
                  ref: msg.ref,
                  topic: "phoenix",
                  event: "phx_reply",
                  payload: ["response": [:]]
                )
              )
            } else if msg.event == "phx_join" {
              joinEventCount.withValue { $0 += 1 }
            }
          }
        }
        defer { serverTask.cancel() }

        try await sut.connect()
        await testClock.advance(by: heartbeatInterval)

        let subscribeTask = Task {
          try await channel.subscribe()
        }

        await testClock.advance(by: timeout)
        subscribeTask.cancel()

        do {
          try await subscribeTask.value
          Issue.record("Expected cancellation error but got success")
        } catch is CancellationError {
        } catch {
          Issue.record("Expected CancellationError but got: \(error)")
        }
        await testClock.advance(by: .seconds(5.0))

        let events = client.sentEvents.compactMap { $0.realtimeMessage }.filter {
          $0.event == "phx_join"
        }

        #expect(events.count == 1)
        #expect(await channel.status == .unsubscribed)
      }
    }

    @Test(.requiresMainSerialExecutor)
    func heartbeat() async throws {
      try await withMainSerialExecutor {
        let heartbeatCount = LockIsolated(0)

        let serverTask = Task { @Sendable [server = server] in
          for await event in server.events {
            guard let msg = event.realtimeMessage else { continue }
            if msg.event == "heartbeat" {
              heartbeatCount.withValue { $0 += 1 }
              server.send(
                RealtimeMessageV2(
                  joinRef: msg.joinRef,
                  ref: msg.ref,
                  topic: "phoenix",
                  event: "phx_reply",
                  payload: [
                    "response": [:],
                    "status": "ok",
                  ]
                )
              )
            }
          }
        }
        defer { serverTask.cancel() }

        let heartbeatStatuses = collect(sut.heartbeats)
        defer { heartbeatStatuses.task.cancel() }

        try await sut.connect()

        await testClock.advance(by: heartbeatInterval * 2)

        let sawTwoHeartbeats = await waitUntil(timeout: 30) {
          heartbeatCount.value >= 2 && heartbeatStatuses.values.value.count >= 4
        }
        #expect(sawTwoHeartbeats)

        expectNoDifference(heartbeatStatuses.values.value, [.sent, .ok, .sent, .ok])
      }
    }

    @Test
    func heartbeat_whenNoResponse_shouldReconnect() async throws {
      try await withMainSerialExecutor {
        let sentHeartbeat = LockIsolated(false)

        let serverTask = Task { @Sendable [server = server] in
          for await event in server.events {
            if event.realtimeMessage?.event == "heartbeat" {
              sentHeartbeat.setValue(true)
            }
          }
        }
        defer { serverTask.cancel() }

        let statuses = collect(sut.statusChanges)
        defer { statuses.task.cancel() }

        try await sut.connect()
        await testClock.advance(by: heartbeatInterval)

        let didSendHeartbeat = await waitUntil(timeout: 15) { sentHeartbeat.value }
        #expect(didSendHeartbeat)

        let pendingHeartbeatRef = await sut.pendingHeartbeatRef
        #expect(pendingHeartbeatRef != nil)

        await testClock.advance(by: heartbeatInterval)

        await testClock.advance(by: reconnectDelay)

        await waitUntil(timeout: 5) { statuses.values.value.count >= 5 }
        // A heartbeat timeout moves the client straight to `.connecting` while it reconnects:
        // `RealtimeClient` no longer publishes an intermediate `.disconnected`.
        #expect(
          statuses.values.value
            == [
              .disconnected,
              .connecting,
              .connected,
              .connecting,
              .connected,
            ]
        )
      }
    }

    /// `heartbeats` consumers — it's an internal bookkeeping signal, not a
    /// heartbeat outcome.
    @Test
    func heartbeat_doesNotLeakDisconnectedStatus() async throws {
      try await withMainSerialExecutor {
        let (client, server) = FakeWebSocket.fakes()
        let sut = RealtimeClient(
          url: url,
          options: RealtimeClientOptions(
            headers: ["apikey": apiKey],
            heartbeatInterval: .seconds(1),
            reconnectDelay: .seconds(10),
            accessToken: { "custom.access.token" }
          ),
          wsTransport: { _, _ in client },
          http: HTTPClient(transport: http),
          clock: testClock
        )

        let heartbeatStatuses = collect(sut.heartbeats)
        defer { heartbeatStatuses.task.cancel() }

        try await sut.connect()

        server.close(code: nil, reason: "boom")
        for await status in sut.statusChanges where status == .connecting { break }

        await testClock.advance(by: .seconds(1))

        #expect(
          !heartbeatStatuses.values.value.contains(.disconnected),
          "heartbeat status leaked .disconnected to consumers: \(heartbeatStatuses.values.value)"
        )

        await sut.disconnect()
      }
    }

    @Test
    func heartbeat_timeout() async throws {
      try await withMainSerialExecutor {
        let heartbeatStatuses = collect(sut.heartbeats)
        defer { heartbeatStatuses.task.cancel() }

        try await sut.connect()
        await testClock.advance(by: heartbeatInterval)

        await waitUntil(timeout: 5) { !heartbeatStatuses.values.value.isEmpty }
        #expect(heartbeatStatuses.values.value == [.sent])

        await testClock.advance(by: timeout)

        await testClock.advance(by: heartbeatInterval)

        await waitUntil(timeout: 5) { heartbeatStatuses.values.value.count >= 2 }
        #expect(heartbeatStatuses.values.value == [.sent, .timeout])
      }
    }

    @Test(.requiresMainSerialExecutor)
    func redundantConnect_doesNotDropIncomingFrames() async throws {
      try await withMainSerialExecutor {
        let serverTask = Task { @Sendable [server = server] in
          for await event in server.events {
            guard let msg = event.realtimeMessage else { continue }
            if msg.event == "heartbeat" {
              server.send(
                RealtimeMessageV2(
                  joinRef: msg.joinRef,
                  ref: msg.ref,
                  topic: "phoenix",
                  event: "phx_reply",
                  payload: [
                    "response": [:],
                    "status": "ok",
                  ]
                )
              )
            }
          }
        }
        defer { serverTask.cancel() }

        let heartbeatStatuses = collect(sut.heartbeats)
        defer { heartbeatStatuses.task.cancel() }

        try await sut.connect()

        // A redundant connect() — the client is already `.connected`, so it is a
        // no-op. The socket must keep receiving frames afterwards.
        try await sut.connect()

        await testClock.advance(by: heartbeatInterval)

        await waitUntil(timeout: 5) { heartbeatStatuses.values.value.count >= 2 }
        #expect(heartbeatStatuses.values.value == [.sent, .ok])
      }
    }

    @Test
    func broadcastWithHTTP() async throws {
      try await withMainSerialExecutor {
        http.respond(when: { $0.url?.path.contains("/api/broadcast/") == true }) { _, _ in
          (HTTPResponse(status: .init(code: 202)), "{}".data(using: .utf8)!)
        }

        let channel = await sut.channel("public:messages") {
          $0.broadcast.acknowledgeBroadcasts = true
        }

        // `broadcast` on a channel that is not subscribed no longer falls back to the REST
        // endpoint: its handle fails with `.notSubscribed` and no request goes out. REST
        // delivery is the explicit `httpSend`, which expects a 202.
        let push = await channel.broadcast(event: "test", message: ["value": 42] as JSONObject)
        #expect((push.error as? RealtimeError)?.kind == .notSubscribed)
        #expect(http.requests.isEmpty)

        try await channel.httpSend(event: "test", message: ["value": 42] as JSONObject)

        let request = try #require(http.requests.last)
        var urlRequest = try #require(URLRequest(httpRequest: request.head))
        urlRequest.httpBody = request.body
        assertInlineSnapshot(of: urlRequest, as: .curl) {
          #"""
          curl \
          	--request POST \
          	--header "Authorization: Bearer custom.access.token" \
          	--header "Content-Type: application/json" \
          	--header "apiKey: publishable.api.key" \
          	--data "{\"value\":42}" \
          	"http://localhost:54321/realtime/v1/api/broadcast/public%3Amessages/events/test"
          """#
        }
      }
    }

    @Test
    func setAuth() async {
      await withMainSerialExecutor {
        let validToken =
          "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyLCJleHAiOjY0MDkyMjExMjAwfQ.GfiEKLl36X8YWcatHg31jRbilovlGecfUKnOyXMSX9c"
        await sut.setAuth(validToken)

        #expect(await sut.accessToken == validToken)
      }
    }

    @Test
    func setAuthWithNonJWT() async throws {
      await withMainSerialExecutor {
        let token = "sb-token"
        await sut.setAuth(token)
      }
    }

    @Test
    func setAuthKeepsCurrentTokenWhenAccessTokenFetchFails() async {
      await withMainSerialExecutor {
        struct FetchError: Error {}

        let sut = RealtimeClient(
          url: url,
          options: RealtimeClientOptions(
            headers: ["apikey": apiKey],
            accessToken: { throw FetchError() }
          ),
          wsTransport: { [client = self.client] _, _ in client },
          http: HTTPClient(transport: http),
          clock: testClock
        )

        let validToken =
          "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyLCJleHAiOjY0MDkyMjExMjAwfQ.GfiEKLl36X8YWcatHg31jRbilovlGecfUKnOyXMSX9c"
        await sut.setAuth(validToken)
        #expect(await sut.accessToken == validToken)

        await sut.setAuth()

        #expect(await sut.accessToken == validToken)
        await sut.disconnect()
      }
    }

    @Test
    func setAuthDoesNotPushNullTokenToChannelsWhenFetchFails() async throws {
      try await withMainSerialExecutor {
        struct FetchError: Error {}

        let validToken =
          "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyLCJleHAiOjY0MDkyMjExMjAwfQ.GfiEKLl36X8YWcatHg31jRbilovlGecfUKnOyXMSX9c"
        let shouldThrow = LockIsolated(false)

        let sut = RealtimeClient(
          url: url,
          options: RealtimeClientOptions(
            headers: ["apikey": apiKey],
            accessToken: {
              if shouldThrow.value { throw FetchError() }
              return validToken
            }
          ),
          wsTransport: { [client = self.client] _, _ in client },
          http: HTTPClient(transport: http),
          clock: testClock
        )

        let serverTask = Task { @Sendable [server = server] in
          for await event in server.events {
            guard let msg = event.realtimeMessage else { continue }
            if msg.event == "heartbeat" {
              server.send(
                RealtimeMessageV2(
                  joinRef: msg.joinRef, ref: msg.ref, topic: "phoenix",
                  event: "phx_reply", payload: ["response": [:]]
                )
              )
            } else if msg.event == "phx_join" {
              server.send(
                RealtimeMessageV2(
                  joinRef: msg.joinRef, ref: msg.ref, topic: msg.topic,
                  event: "phx_reply",
                  payload: ["response": ["postgres_changes": .array([])], "status": "ok"]
                )
              )
            }
          }
        }
        defer { serverTask.cancel() }

        try await sut.connect()
        await sut.setAuth(validToken)
        #expect(await sut.accessToken == validToken)

        let channel = await sut.channel("room")
        try await channel.subscribe()

        let sentBefore = client.sentEvents.count
        shouldThrow.setValue(true)
        await sut.setAuth()

        let accessTokenPushes =
          client.sentEvents
          .dropFirst(sentBefore)
          .compactMap { $0.realtimeMessage }
          .filter { $0.event == ChannelEvent.accessToken }
        #expect(
          accessTokenPushes.isEmpty,
          "No access_token update should be pushed to channels when the token fetch fails"
        )
        #expect(await sut.accessToken == validToken)

        await sut.disconnect()
      }
    }

    @Test
    func listenForMessagesCancelsExistingTask() async throws {
      try await withMainSerialExecutor {
        try await sut.connect()

        let firstMessageTask = await sut.messageTask
        #expect(firstMessageTask != nil)
        #expect(!(firstMessageTask?.isCancelled ?? true))

        await sut.disconnect()
        try await sut.connect()

        #expect(firstMessageTask?.isCancelled ?? false)

        let secondMessageTask = await sut.messageTask
        #expect(secondMessageTask != nil)
        #expect(!(secondMessageTask?.isCancelled ?? true))
      }
    }

    @Test
    func startHeartbeatingCancelsExistingTask() async throws {
      try await withMainSerialExecutor {
        try await sut.connect()

        let firstHeartbeatTask = await sut.heartbeatTask
        #expect(firstHeartbeatTask != nil)
        #expect(!(firstHeartbeatTask?.isCancelled ?? true))

        await sut.disconnect()
        try await sut.connect()

        #expect(firstHeartbeatTask?.isCancelled ?? false)

        let secondHeartbeatTask = await sut.heartbeatTask
        #expect(secondHeartbeatTask != nil)
        #expect(!(secondHeartbeatTask?.isCancelled ?? true))
      }
    }

    @Test
    func messageProcessingRespectsCancellation() async throws {
      try await withMainSerialExecutor {
        let messagesProcessed = LockIsolated(0)

        try await sut.connect()

        for i in 1...3 {
          server.send(
            RealtimeMessageV2(
              joinRef: nil,
              ref: "\(i)",
              topic: "test-topic",
              event: "test-event",
              payload: ["index": .double(Double(i))]
            )
          )
          messagesProcessed.withValue { $0 += 1 }
        }

        await sut.disconnect()

        for i in 4...6 {
          server.send(
            RealtimeMessageV2(
              joinRef: nil,
              ref: "\(i)",
              topic: "test-topic",
              event: "test-event",
              payload: ["index": .double(Double(i))]
            )
          )
        }

        #expect(await sut.messageTask == nil, "Message task should be nil after disconnect")
      }
    }

    @Test
    func multipleReconnectionsHandleTaskLifecycleCorrectly() async throws {
      try await withMainSerialExecutor {
        var previousMessageTasks: [Task<Void, Never>?] = []
        var previousHeartbeatTasks: [Task<Void, Never>?] = []

        for _ in 1...3 {
          try await sut.connect()

          await waitUntil { [sut = sut] in
            let messageTask = await sut.messageTask
            let heartbeatTask = await sut.heartbeatTask
            return messageTask != nil
              && heartbeatTask != nil
              && !(messageTask?.isCancelled ?? true)
              && !(heartbeatTask?.isCancelled ?? true)
          }

          let messageTask = await sut.messageTask
          let heartbeatTask = await sut.heartbeatTask

          #expect(messageTask != nil)
          #expect(heartbeatTask != nil)
          #expect(!(messageTask?.isCancelled ?? true))
          #expect(!(heartbeatTask?.isCancelled ?? true))

          previousMessageTasks.append(messageTask)
          previousHeartbeatTasks.append(heartbeatTask)

          await sut.disconnect()

          await waitUntil {
            (messageTask?.isCancelled ?? false) && (heartbeatTask?.isCancelled ?? false)
          }

          #expect(messageTask?.isCancelled ?? false)
          #expect(heartbeatTask?.isCancelled ?? false)
        }

        for task in previousMessageTasks {
          await waitUntil { task?.isCancelled ?? false }
          #expect(task?.isCancelled ?? false)
        }

        for task in previousHeartbeatTasks {
          await waitUntil { task?.isCancelled ?? false }
          #expect(task?.isCancelled ?? false)
        }
      }
    }

    @Test
    func deferredDisconnect_disconnectsAfterDelay() async throws {
      try await withMainSerialExecutor {
        let deferredSut = makeClientWithDeferredDisconnect(delay: .seconds(5))

        try await deferredSut.connect()
        #expect(await deferredSut.status == .connected)

        let channel = await deferredSut.channel("test:deferred")
        await deferredSut.removeChannel(channel)

        #expect(await deferredSut.status == .connected)
        #expect(await deferredSut.pendingDisconnectTask != nil)

        await testClock.advance(by: .seconds(5))

        #expect(await deferredSut.status == .disconnected)
        #expect(await deferredSut.pendingDisconnectTask == nil)
      }
    }

    @Test
    func deferredDisconnect_cancelledByNewChannel() async throws {
      try await withMainSerialExecutor {
        let deferredSut = makeClientWithDeferredDisconnect(delay: .seconds(5))

        try await deferredSut.connect()

        let channel = await deferredSut.channel("test:deferred")
        await deferredSut.removeChannel(channel)

        #expect(await deferredSut.status == .connected)
        let pendingTask = await deferredSut.pendingDisconnectTask
        #expect(pendingTask != nil)

        _ = await deferredSut.channel("test:new")

        #expect(await deferredSut.pendingDisconnectTask == nil)
        #expect(pendingTask?.isCancelled ?? false)

        await testClock.advance(by: .seconds(5))
        #expect(await deferredSut.status == .connected)

        await deferredSut.disconnect()
      }
    }

    @Test
    func deferredDisconnect_cancelledByDirectDisconnect() async throws {
      try await withMainSerialExecutor {
        let deferredSut = makeClientWithDeferredDisconnect(delay: .seconds(5))

        try await deferredSut.connect()

        let channel = await deferredSut.channel("test:deferred")
        await deferredSut.removeChannel(channel)

        let pendingTask = await deferredSut.pendingDisconnectTask
        #expect(pendingTask != nil)

        await deferredSut.disconnect()

        #expect(pendingTask?.isCancelled ?? false)
        #expect(await deferredSut.pendingDisconnectTask == nil)
      }
    }

    @Test
    func removeAllChannels_disconnectsImmediately_withDeferredOption() async throws {
      try await withMainSerialExecutor {
        let deferredSut = makeClientWithDeferredDisconnect(delay: .seconds(5))

        try await deferredSut.connect()

        _ = await deferredSut.channel("test:ch1")
        _ = await deferredSut.channel("test:ch2")

        await deferredSut.removeAllChannels()

        #expect(await deferredSut.status == .disconnected)
        #expect(await deferredSut.pendingDisconnectTask == nil)
      }
    }

    private func makeClientWithDeferredDisconnect(delay: Duration) -> RealtimeClient {
      RealtimeClient(
        url: url,
        options: RealtimeClientOptions(
          headers: ["apikey": apiKey],
          disconnectOnEmptyChannelsAfter: delay
        ),
        wsTransport: { [client = self.client] _, _ in client },
        http: HTTPClient(transport: http),
        clock: testClock
      )
    }
  }

  /// The loop tasks by their old names, read out of the client's `TaskStorage`.
  extension RealtimeClient {
    fileprivate var messageTask: Task<Void, Never>? { tasks.tasks(at: .socketReader).first }
    fileprivate var heartbeatTask: Task<Void, Never>? { tasks.tasks(at: .heartbeat).first }
    fileprivate var pendingDisconnectTask: Task<Void, Never>? {
      tasks.tasks(at: .idleDisconnect).first
    }
  }

#endif

extension RealtimeMessageV2 {
  static let messagesSubscribed = Self(
    joinRef: nil,
    ref: "2",
    topic: "realtime:public:messages",
    event: "phx_reply",
    payload: [
      "response": [
        "postgres_changes": [
          ["id": 43_783_255, "event": "INSERT", "schema": "public", "table": "messages"],
          ["id": 124_973_000, "event": "UPDATE", "schema": "public", "table": "messages"],
          ["id": 85_243_397, "event": "DELETE", "schema": "public", "table": "messages"],
        ]
      ],
      "status": "ok",
    ]
  )
}

extension FakeWebSocket {
  func send(_ message: RealtimeMessageV2) {
    let serializer = RealtimeSerializer()
    try! self.send(serializer.encodeText(message))
  }
}

extension LegacyWebSocketEvent {
  var json: Any {
    switch self {
    case .binary(let data):
      let json = try? JSONSerialization.jsonObject(with: data)
      return ["binary": json]
    case .text(let text):
      let json = try? JSONSerialization.jsonObject(with: Data(text.utf8))
      return ["text": json]
    case .close(let code, let reason):
      return [
        "close": [
          "code": code as Any,
          "reason": reason,
        ]
      ]
    }
  }

  var realtimeMessage: RealtimeMessageV2? {
    guard case .text(let text) = self else { return nil }
    let serializer = RealtimeSerializer()
    return try? serializer.decodeText(text)
  }
}
