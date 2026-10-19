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

  @Suite(.serialized, .mainSerialExecutorSerialized)
  final class RealtimeTests: Sendable {
    let url = URL(string: "http://localhost:54321/realtime/v1")!
    let apiKey = "publishable.api.key"

    let server: FakeWebSocket
    let client: FakeWebSocket
    let http: RecordingTransport
    let sut: RealtimeClientV2
    let testClock: TestClock<Duration>

    let heartbeatInterval = RealtimeClientOptions.defaultHeartbeatInterval
    let reconnectDelay = RealtimeClientOptions.defaultReconnectDelay
    let timeout = RealtimeClientOptions.defaultTimeout

    init() {
      let (client, server) = FakeWebSocket.fakes()
      self.client = client
      self.server = server
      http = RecordingTransport()
      testClock = TestClock()

      sut = RealtimeClientV2(
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

    deinit {
      sut.disconnect()
    }

    @Test
    func transport() async {
      await withMainSerialExecutor {
        let client = RealtimeClientV2(
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

        await client.connect()
      }
    }

    @Test
    func behavior() async throws {
      try await withMainSerialExecutor {
        let channel = sut.channel("public:messages")
        var subscriptions: Set<ObservationToken> = []

        channel.onPostgresChange(InsertAction.self, table: "messages") { _ in
        }
        .store(in: &subscriptions)

        channel.onPostgresChange(UpdateAction.self, table: "messages") { _ in
        }
        .store(in: &subscriptions)

        channel.onPostgresChange(DeleteAction.self, table: "messages") { _ in
        }
        .store(in: &subscriptions)

        let socketStatuses = LockIsolated([RealtimeClientStatus]())

        sut.onStatusChange { status in
          socketStatuses.withValue { $0.append(status) }
        }
        .store(in: &subscriptions)

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

        let channelStatuses = LockIsolated([RealtimeChannelStatus]())
        channel.onStatusChange { status in
          channelStatuses.withValue {
            $0.append(status)
          }
        }
        .store(in: &subscriptions)

        do {
          try await channel.subscribeWithError()
        } catch {
          Issue.record("Expected .subscribed but got error: \(error)")
        }
        #expect(channelStatuses.value == [.unsubscribed, .subscribing, .subscribed])

        #expect(
          Array(socketStatuses.value.prefix(3))
            == [.disconnected, .connecting, .connected]
        )

        let messageTask = sut.mutableState.messageTask
        #expect(messageTask != nil)

        let heartbeatTask = sut.mutableState.heartbeatTask
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
        let channel = sut.channel("public:messages")
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

        await sut.connect()
        await testClock.advance(by: heartbeatInterval)

        Task {
          try await channel.subscribeWithError()
        }

        await testClock.advance(by: timeout)

        await testClock.advance(by: .seconds(2.5))

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
              "join_ref" : "1",
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
              "ref" : "1",
              "topic" : "realtime:public:messages"
            },
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
        let channel = sut.channel("public:messages")
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

        await sut.connect()
        await testClock.advance(by: heartbeatInterval)

        let subscribeTask = Task {
          _ = try? await channel.subscribeWithError()
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
        #expect(channel.status == .subscribed)
      }
    }

    @Test(.requiresMainSerialExecutor)
    func subscribeTimeout_failsAfterMaxRetries() async throws {
      try await withMainSerialExecutor {
        let channel = sut.channel("public:messages")
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

        await sut.connect()
        await testClock.advance(by: heartbeatInterval)

        let subscribeTask = Task {
          try await channel.subscribeWithError()
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
        #expect(channel.status == .unsubscribed)
      }
    }

    @Test
    func subscribeTimeout_cancelsOnTaskCancel() async throws {
      try await withMainSerialExecutor {
        let channel = sut.channel("public:messages")
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

        await sut.connect()
        await testClock.advance(by: heartbeatInterval)

        let subscribeTask = Task {
          try await channel.subscribeWithError()
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
        #expect(channel.status == .unsubscribed)
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

        let heartbeatStatuses = LockIsolated<[HeartbeatStatus]>([])
        let subscription = sut.onHeartbeat { status in
          heartbeatStatuses.withValue {
            $0.append(status)
          }
        }
        defer { subscription.cancel() }

        await sut.connect()

        await testClock.advance(by: heartbeatInterval * 2)

        let sawTwoHeartbeats = await waitUntil(timeout: 30) { heartbeatCount.value >= 2 }
        #expect(sawTwoHeartbeats)

        expectNoDifference(heartbeatStatuses.value, [.sent, .ok, .sent, .ok])
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

        let statuses = LockIsolated<[RealtimeClientStatus]>([])
        let subscription = sut.onStatusChange { status in
          statuses.withValue {
            $0.append(status)
          }
        }
        defer { subscription.cancel() }

        await sut.connect()
        await testClock.advance(by: heartbeatInterval)

        let didSendHeartbeat = await waitUntil(timeout: 15) { sentHeartbeat.value }
        #expect(didSendHeartbeat)

        let pendingHeartbeatRef = sut.mutableState.pendingHeartbeatRef
        #expect(pendingHeartbeatRef != nil)

        await testClock.advance(by: heartbeatInterval)

        await testClock.advance(by: reconnectDelay)

        #expect(
          statuses.value
            == [
              .disconnected,
              .connecting,
              .connected,
              .disconnected,
              .connecting,
              .connected,
            ]
        )
      }
    }

    @Test
    func heartbeat_doesNotLeakDisconnectedStatus() async throws {
      try await withMainSerialExecutor {
        let (client, server) = FakeWebSocket.fakes()
        let sut = RealtimeClientV2(
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
        defer { sut.disconnect() }

        let heartbeatStatuses = LockIsolated<[HeartbeatStatus]>([])
        let subscription = sut.onHeartbeat { status in
          heartbeatStatuses.withValue { $0.append(status) }
        }
        defer { subscription.cancel() }

        await sut.connect()

        server.close(code: nil, reason: "boom")
        await Task.megaYield()

        await testClock.advance(by: .seconds(1))

        #expect(
          !heartbeatStatuses.value.contains(.disconnected),
          "heartbeat status leaked .disconnected to consumers: \(heartbeatStatuses.value)"
        )
      }
    }

    @Test
    func heartbeat_timeout() async throws {
      try await withMainSerialExecutor {
        let heartbeatStatuses = LockIsolated<[HeartbeatStatus]>([])
        let s1 = sut.onHeartbeat { status in
          heartbeatStatuses.withValue {
            $0.append(status)
          }
        }
        defer { s1.cancel() }

        await sut.connect()
        await testClock.advance(by: heartbeatInterval)

        #expect(heartbeatStatuses.value == [.sent])

        await testClock.advance(by: timeout)

        await testClock.advance(by: heartbeatInterval)

        #expect(heartbeatStatuses.value == [.sent, .timeout])
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

        let heartbeatStatuses = LockIsolated<[HeartbeatStatus]>([])
        let subscription = sut.onHeartbeat { status in
          heartbeatStatuses.withValue { $0.append(status) }
        }
        defer { subscription.cancel() }

        await sut.connect()

        await sut.connect()
        await Task.megaYield()

        await testClock.advance(by: heartbeatInterval)
        await Task.megaYield()

        #expect(heartbeatStatuses.value == [.sent, .ok])
      }
    }

    @Test
    func broadcastWithHTTP() async throws {
      try await withMainSerialExecutor {
        http.respond(when: { $0.url?.path.contains("/api/broadcast/") == true }) { _, _ in
          (HTTPResponse(status: .init(code: 200)), "{}".data(using: .utf8)!)
        }

        let channel = sut.channel("public:messages") {
          $0.broadcast.acknowledgeBroadcasts = true
        }

        try await channel.broadcast(event: "test", message: ["value": 42])

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

        #expect(sut.mutableState.accessToken == validToken)
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

        let sut = RealtimeClientV2(
          url: url,
          options: RealtimeClientOptions(
            headers: ["apikey": apiKey],
            accessToken: { throw FetchError() }
          ),
          wsTransport: { [client = self.client] _, _ in client },
          http: HTTPClient(transport: http),
          clock: testClock
        )
        defer { sut.disconnect() }

        let validToken =
          "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyLCJleHAiOjY0MDkyMjExMjAwfQ.GfiEKLl36X8YWcatHg31jRbilovlGecfUKnOyXMSX9c"
        await sut.setAuth(validToken)
        #expect(sut.mutableState.accessToken == validToken)

        await sut.setAuth()

        #expect(sut.mutableState.accessToken == validToken)
      }
    }

    @Test
    func setAuthDoesNotPushNullTokenToChannelsWhenFetchFails() async throws {
      try await withMainSerialExecutor {
        struct FetchError: Error {}

        let validToken =
          "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyLCJleHAiOjY0MDkyMjExMjAwfQ.GfiEKLl36X8YWcatHg31jRbilovlGecfUKnOyXMSX9c"
        let shouldThrow = LockIsolated(false)

        let sut = RealtimeClientV2(
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
        defer { sut.disconnect() }

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

        await sut.connect()
        await sut.setAuth(validToken)
        #expect(sut.mutableState.accessToken == validToken)

        let channel = sut.channel("room")
        try await channel.subscribeWithError()

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
        #expect(sut.mutableState.accessToken == validToken)
      }
    }

    @Test
    func listenForMessagesCancelsExistingTask() async {
      await withMainSerialExecutor {
        await sut.connect()

        let firstMessageTask = sut.mutableState.messageTask
        #expect(firstMessageTask != nil)
        #expect(!(firstMessageTask?.isCancelled ?? true))

        sut.disconnect()
        await sut.connect()

        #expect(firstMessageTask?.isCancelled ?? false)

        let secondMessageTask = sut.mutableState.messageTask
        #expect(secondMessageTask != nil)
        #expect(!(secondMessageTask?.isCancelled ?? true))
      }
    }

    @Test
    func startHeartbeatingCancelsExistingTask() async {
      await withMainSerialExecutor {
        await sut.connect()

        let firstHeartbeatTask = sut.mutableState.heartbeatTask
        #expect(firstHeartbeatTask != nil)
        #expect(!(firstHeartbeatTask?.isCancelled ?? true))

        sut.disconnect()
        await sut.connect()

        #expect(firstHeartbeatTask?.isCancelled ?? false)

        let secondHeartbeatTask = sut.mutableState.heartbeatTask
        #expect(secondHeartbeatTask != nil)
        #expect(!(secondHeartbeatTask?.isCancelled ?? true))
      }
    }

    @Test
    func messageProcessingRespectsCancellation() async {
      await withMainSerialExecutor {
        let messagesProcessed = LockIsolated(0)

        await sut.connect()

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

        await Task.megaYield()

        sut.disconnect()

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

        await Task.megaYield()

        #expect(sut.mutableState.messageTask == nil, "Message task should be nil after disconnect")
      }
    }

    @Test
    func multipleReconnectionsHandleTaskLifecycleCorrectly() async {
      await withMainSerialExecutor {
        var previousMessageTasks: [Task<Void, Never>?] = []
        var previousHeartbeatTasks: [Task<Void, Never>?] = []

        for _ in 1...3 {
          await sut.connect()

          await waitUntil { [sut = sut] in
            let messageTask = sut.mutableState.messageTask
            let heartbeatTask = sut.mutableState.heartbeatTask
            return messageTask != nil
              && heartbeatTask != nil
              && !(messageTask?.isCancelled ?? true)
              && !(heartbeatTask?.isCancelled ?? true)
          }

          let messageTask = sut.mutableState.messageTask
          let heartbeatTask = sut.mutableState.heartbeatTask

          #expect(messageTask != nil)
          #expect(heartbeatTask != nil)
          #expect(!(messageTask?.isCancelled ?? true))
          #expect(!(heartbeatTask?.isCancelled ?? true))

          previousMessageTasks.append(messageTask)
          previousHeartbeatTasks.append(heartbeatTask)

          sut.disconnect()

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
    func deferredDisconnect_disconnectsAfterDelay() async {
      await withMainSerialExecutor {
        let deferredSut = makeClientWithDeferredDisconnect(delay: .seconds(5))
        defer { deferredSut.disconnect() }

        await deferredSut.connect()
        #expect(deferredSut.status == .connected)

        let channel = deferredSut.channel("test:deferred")
        await deferredSut.removeChannel(channel)

        #expect(deferredSut.status == .connected)
        #expect(deferredSut.mutableState.pendingDisconnectTask != nil)

        await testClock.advance(by: .seconds(5))

        #expect(deferredSut.status == .disconnected)
        #expect(deferredSut.mutableState.pendingDisconnectTask == nil)
      }
    }

    @Test
    func deferredDisconnect_cancelledByNewChannel() async {
      await withMainSerialExecutor {
        let deferredSut = makeClientWithDeferredDisconnect(delay: .seconds(5))
        defer { deferredSut.disconnect() }

        await deferredSut.connect()

        let channel = deferredSut.channel("test:deferred")
        await deferredSut.removeChannel(channel)

        #expect(deferredSut.status == .connected)
        #expect(deferredSut.mutableState.pendingDisconnectTask != nil)
        let pendingTask = deferredSut.mutableState.pendingDisconnectTask

        _ = deferredSut.channel("test:new")

        #expect(deferredSut.mutableState.pendingDisconnectTask == nil)
        #expect(pendingTask?.isCancelled ?? false)

        await testClock.advance(by: .seconds(5))
        #expect(deferredSut.status == .connected)
      }
    }

    @Test
    func deferredDisconnect_cancelledByDirectDisconnect() async {
      await withMainSerialExecutor {
        let deferredSut = makeClientWithDeferredDisconnect(delay: .seconds(5))

        await deferredSut.connect()

        let channel = deferredSut.channel("test:deferred")
        await deferredSut.removeChannel(channel)

        let pendingTask = deferredSut.mutableState.pendingDisconnectTask
        #expect(pendingTask != nil)

        deferredSut.disconnect()

        #expect(pendingTask?.isCancelled ?? false)
        #expect(deferredSut.mutableState.pendingDisconnectTask == nil)
      }
    }

    @Test
    func removeAllChannels_disconnectsImmediately_withDeferredOption() async {
      await withMainSerialExecutor {
        let deferredSut = makeClientWithDeferredDisconnect(delay: .seconds(5))
        defer { deferredSut.disconnect() }

        await deferredSut.connect()

        _ = deferredSut.channel("test:ch1")
        _ = deferredSut.channel("test:ch2")

        await deferredSut.removeAllChannels()

        #expect(deferredSut.status == .disconnected)
        #expect(deferredSut.mutableState.pendingDisconnectTask == nil)
      }
    }

    private func makeClientWithDeferredDisconnect(delay: Duration) -> RealtimeClientV2 {
      RealtimeClientV2(
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
