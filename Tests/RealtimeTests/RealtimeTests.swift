import Clocks
import ConcurrencyExtras
import CustomDump
import Foundation
import InlineSnapshotTesting
import TestHelpers
import Testing

@testable import Realtime
@testable import RealtimeV2

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

#if os(Linux)
  // RealtimeTests are disabled on Linux due to timing flakiness.
#else

  // `withMainSerialExecutor` mutates a process-global flag (ConcurrencyExtras'
  // `uncheckedUseMainSerialExecutor`) to force deterministic task scheduling within its closure.
  // Swift Testing runs tests in the same suite concurrently by default, so two tests racing to
  // flip that global would interfere with each other — serialize this suite, mirroring the
  // `_clock`-swap precedent in PostgrestBuilderTests (PR #1095).
  @Suite(.serialized)
  final class RealtimeTests: Sendable {
    let url = URL(string: "http://localhost:54321/realtime/v1")!
    let apiKey = "publishable.api.key"

    let server: FakeWebSocket
    let client: FakeWebSocket
    let http: HTTPClientMock
    let sut: RealtimeClientV2
    let testClock: TestClock<Duration>

    let heartbeatInterval: TimeInterval = RealtimeClientOptions.defaultHeartbeatInterval
    let reconnectDelay: TimeInterval = RealtimeClientOptions.defaultReconnectDelay
    let timeoutInterval: TimeInterval = RealtimeClientOptions.defaultTimeoutInterval

    init() {
      let (client, server) = FakeWebSocket.fakes()
      self.client = client
      self.server = server
      http = HTTPClientMock()
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
        http: http,
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
          wsTransport: { url, headers in
            assertInlineSnapshot(of: url, as: .description) {
              """
              ws://localhost:54321/realtime/v1/websocket?apikey=publishable.api.key&vsn=2.0.0&log_level=warn
              """
            }
            return FakeWebSocket.fakes().0
          },
          http: http,
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

        // Set up server to respond to heartbeats and phx_join
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

        // Wait until it subscribes to assert WS events
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

    @Test
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
              // Skip first join.
              if joinEventCount.value == 2 {
                server.send(.messagesSubscribed)
              }
            }
          }
        }
        defer { serverTask.cancel() }

        await sut.connect()
        await testClock.advance(by: .seconds(heartbeatInterval))

        Task {
          try await channel.subscribeWithError()
        }

        // Wait for the timeout for rejoining.
        await testClock.advance(by: .seconds(timeoutInterval))

        // Wait for the retry delay (base delay is 1.0s, but we need to account for jitter)
        // The retry delay is calculated as: baseDelay * pow(2, attempt-1) + jitter
        // For attempt 2: 1.0 * pow(2, 1) = 2.0s + jitter (up to ±25% = ±0.5s)
        // So we need to wait at least 2.5s to ensure the retry happens
        await testClock.advance(by: .seconds(2.5))

        let events = client.sentEvents.compactMap { $0.realtimeMessage }.filter {
          $0.event == "phx_join"
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

    // Succeeds after 2 retries (on 3rd attempt)
    @Test
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
              // Respond on the 3rd attempt
              if joinEventCount.value == successAttempt {
                server.send(.messagesSubscribed)
              }
            }
          }
        }
        defer { serverTask.cancel() }

        await sut.connect()
        await testClock.advance(by: .seconds(heartbeatInterval))

        let subscribeTask = Task {
          _ = try? await channel.subscribeWithError()
        }

        // Wait for each attempt and retry delay
        for attempt in 1..<successAttempt {
          await testClock.advance(by: .seconds(timeoutInterval))
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

    // Fails after max retries (should unsubscribe)
    @Test
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
              // Never respond to any join attempts
            }
          }
        }
        defer { serverTask.cancel() }

        await sut.connect()
        await testClock.advance(by: .seconds(heartbeatInterval))

        let subscribeTask = Task {
          try await channel.subscribeWithError()
        }

        for attempt in 1...5 {
          await testClock.advance(by: .seconds(timeoutInterval))
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

    // Cancels and unsubscribes if the subscribe task is cancelled
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
              // Never respond to any join attempts
            }
          }
        }
        defer { serverTask.cancel() }

        await sut.connect()
        await testClock.advance(by: .seconds(heartbeatInterval))

        let subscribeTask = Task {
          try await channel.subscribeWithError()
        }

        await testClock.advance(by: .seconds(timeoutInterval))
        subscribeTask.cancel()

        do {
          try await subscribeTask.value
          Issue.record("Expected cancellation error but got success")
        } catch is CancellationError {
          // Expected
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

    @Test
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

        await testClock.advance(by: .seconds(heartbeatInterval * 2))

        let sawTwoHeartbeats = await waitUntil(timeout: 3) { heartbeatCount.value >= 2 }
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
            // Intentionally not replying — trigger timeout/reconnect path.
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
        await testClock.advance(by: .seconds(heartbeatInterval))

        let didSendHeartbeat = await waitUntil(timeout: 1) { sentHeartbeat.value }
        #expect(didSendHeartbeat)

        let pendingHeartbeatRef = sut.mutableState.pendingHeartbeatRef
        #expect(pendingHeartbeatRef != nil)

        // Wait until next heartbeat
        await testClock.advance(by: .seconds(heartbeatInterval))

        // Wait for reconnect delay
        await testClock.advance(by: .seconds(reconnectDelay))

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

    /// Regression test for SDK-1330: a heartbeat tick that lands while the
    /// client is mid-reconnect (external close, not one triggered by the
    /// heartbeat timer itself) must not publish `.disconnected` to
    /// `onHeartbeat(_:)`/`heartbeat` consumers — it's an internal bookkeeping
    /// signal, not a heartbeat outcome.
    @Test
    func heartbeat_doesNotLeakDisconnectedStatus() async throws {
      try await withMainSerialExecutor {
        let (client, server) = FakeWebSocket.fakes()
        let sut = RealtimeClientV2(
          url: url,
          options: RealtimeClientOptions(
            headers: ["apikey": apiKey],
            heartbeatInterval: 1,
            reconnectDelay: 10,
            accessToken: { "custom.access.token" }
          ),
          wsTransport: { _, _ in client },
          http: http,
          clock: testClock
        )
        defer { sut.disconnect() }

        let heartbeatStatuses = LockIsolated<[HeartbeatStatus]>([])
        let subscription = sut.onHeartbeat { status in
          heartbeatStatuses.withValue { $0.append(status) }
        }
        defer { subscription.cancel() }

        await sut.connect()

        // Server drops the connection out from under us — unrelated to the
        // heartbeat timer, which is still sleeping out its first interval.
        server.close(code: nil, reason: "boom")
        await Task.megaYield()

        // The heartbeat timer ticks while the reconnect is still sleeping out
        // its 10s `reconnectDelay` — the still-alive old heartbeat task must
        // not observe `status != .connected` and publish `.disconnected`.
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

        // Don't respond to any heartbeats — let the timeout fire naturally.
        await sut.connect()
        await testClock.advance(by: .seconds(heartbeatInterval))

        // First heartbeat sent
        #expect(heartbeatStatuses.value == [.sent])

        // Wait for timeout
        await testClock.advance(by: .seconds(timeoutInterval))

        // Wait for next heartbeat.
        await testClock.advance(by: .seconds(heartbeatInterval))

        // Should have timeout status
        #expect(heartbeatStatuses.value == [.sent, .timeout])
      }
    }

    // Regression test for SDK-959: a second `handleConnected` on an already
    // established connection (e.g. `connect()` called while the socket is
    // already connected, or while an auto-reconnect is in flight) used to
    // re-read `conn.events`. The first event-stream's `onTermination` would
    // then race to nil out the live `onEvent`, leaving the socket connected
    // but deaf — heartbeat and `phx_join` replies were silently dropped,
    // stalling subscribe for tens of seconds to minutes.
    @Test
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

        // A redundant connect() — the ConnectionManager is already `.connected`,
        // so it returns the same connection. The socket must keep receiving
        // frames afterwards.
        await sut.connect()
        await Task.megaYield()

        // Drive a heartbeat; the server replies. If the socket is still
        // listening, the reply acks the heartbeat (.ok). If `onEvent` was
        // niled out by the duplicate setup, the reply is dropped and the
        // heartbeat is never acknowledged.
        await testClock.advance(by: .seconds(heartbeatInterval))
        await Task.megaYield()

        #expect(heartbeatStatuses.value == [.sent, .ok])
      }
    }

    @Test
    func broadcastWithHTTP() async throws {
      try await withMainSerialExecutor {
        await http.when {
          $0.url.path.contains("/api/broadcast/")
        } return: { _ in
          HTTPResponse(
            data: "{}".data(using: .utf8)!,
            response: HTTPURLResponse(
              url: self.url,
              statusCode: 200,
              httpVersion: nil,
              headerFields: nil
            )!
          )
        }

        let channel = sut.channel("public:messages") {
          $0.broadcast.acknowledgeBroadcasts = true
        }

        try await channel.broadcast(event: "test", message: ["value": 42])

        let request = await http.receivedRequests.last
        assertInlineSnapshot(of: request?.urlRequest, as: .curl) {
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
          http: http,
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
          http: http,
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

    // MARK: - Task Lifecycle Tests

    @Test
    func listenForMessagesCancelsExistingTask() async {
      await withMainSerialExecutor {
        await sut.connect()

        // Get the first message task
        let firstMessageTask = sut.mutableState.messageTask
        #expect(firstMessageTask != nil)
        #expect(!(firstMessageTask?.isCancelled ?? true))

        // Trigger reconnection which will call listenForMessages again
        sut.disconnect()
        await sut.connect()

        // Verify the old task was cancelled
        #expect(firstMessageTask?.isCancelled ?? false)

        // Verify a new task was created
        let secondMessageTask = sut.mutableState.messageTask
        #expect(secondMessageTask != nil)
        #expect(!(secondMessageTask?.isCancelled ?? true))
      }
    }

    @Test
    func startHeartbeatingCancelsExistingTask() async {
      await withMainSerialExecutor {
        await sut.connect()

        // Get the first heartbeat task
        let firstHeartbeatTask = sut.mutableState.heartbeatTask
        #expect(firstHeartbeatTask != nil)
        #expect(!(firstHeartbeatTask?.isCancelled ?? true))

        // Trigger reconnection which will call startHeartbeating again
        sut.disconnect()
        await sut.connect()

        // Verify the old task was cancelled
        #expect(firstHeartbeatTask?.isCancelled ?? false)

        // Verify a new task was created
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

        // Send multiple messages
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

        // Disconnect to cancel message processing
        sut.disconnect()

        // Try to send more messages after disconnect (these should not be processed)
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

        // Verify that the message task was cancelled and cleaned up
        #expect(sut.mutableState.messageTask == nil, "Message task should be nil after disconnect")
      }
    }

    @Test
    func multipleReconnectionsHandleTaskLifecycleCorrectly() async {
      await withMainSerialExecutor {
        var previousMessageTasks: [Task<Void, Never>?] = []
        var previousHeartbeatTasks: [Task<Void, Never>?] = []

        // Test multiple connect/disconnect cycles
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

          // Verify tasks were cancelled after disconnect
          #expect(messageTask?.isCancelled ?? false)
          #expect(heartbeatTask?.isCancelled ?? false)
        }

        // Verify all previous tasks were properly cancelled
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

    // MARK: - Deferred Disconnect Tests

    @Test
    func deferredDisconnect_disconnectsAfterDelay() async {
      await withMainSerialExecutor {
        let deferredSut = makeClientWithDeferredDisconnect(delay: 5)
        defer { deferredSut.disconnect() }

        await deferredSut.connect()
        #expect(deferredSut.status == .connected)

        let channel = deferredSut.channel("test:deferred")
        await deferredSut.removeChannel(channel)

        // Still connected — pending disconnect has not fired yet.
        #expect(deferredSut.status == .connected)
        #expect(deferredSut.mutableState.pendingDisconnectTask != nil)

        // Advance past the delay — pending task fires and disconnects.
        await testClock.advance(by: .seconds(5))

        #expect(deferredSut.status == .disconnected)
        #expect(deferredSut.mutableState.pendingDisconnectTask == nil)
      }
    }

    @Test
    func deferredDisconnect_cancelledByNewChannel() async {
      await withMainSerialExecutor {
        let deferredSut = makeClientWithDeferredDisconnect(delay: 5)
        defer { deferredSut.disconnect() }

        await deferredSut.connect()

        let channel = deferredSut.channel("test:deferred")
        await deferredSut.removeChannel(channel)

        #expect(deferredSut.status == .connected)
        #expect(deferredSut.mutableState.pendingDisconnectTask != nil)
        let pendingTask = deferredSut.mutableState.pendingDisconnectTask

        // Creating a new channel cancels the pending disconnect.
        _ = deferredSut.channel("test:new")

        #expect(deferredSut.mutableState.pendingDisconnectTask == nil)
        #expect(pendingTask?.isCancelled ?? false)

        // Advance past what would have been the delay — client stays connected.
        await testClock.advance(by: .seconds(5))
        #expect(deferredSut.status == .connected)
      }
    }

    @Test
    func deferredDisconnect_cancelledByDirectDisconnect() async {
      await withMainSerialExecutor {
        let deferredSut = makeClientWithDeferredDisconnect(delay: 5)

        await deferredSut.connect()

        let channel = deferredSut.channel("test:deferred")
        await deferredSut.removeChannel(channel)

        let pendingTask = deferredSut.mutableState.pendingDisconnectTask
        #expect(pendingTask != nil)

        // Calling disconnect() directly cancels the pending timer.
        deferredSut.disconnect()

        #expect(pendingTask?.isCancelled ?? false)
        #expect(deferredSut.mutableState.pendingDisconnectTask == nil)
      }
    }

    @Test
    func removeAllChannels_disconnectsImmediately_withDeferredOption() async {
      await withMainSerialExecutor {
        let deferredSut = makeClientWithDeferredDisconnect(delay: 5)
        defer { deferredSut.disconnect() }

        await deferredSut.connect()

        _ = deferredSut.channel("test:ch1")
        _ = deferredSut.channel("test:ch2")

        await deferredSut.removeAllChannels()

        // removeAllChannels always disconnects immediately, regardless of delay.
        #expect(deferredSut.status == .disconnected)
        #expect(deferredSut.mutableState.pendingDisconnectTask == nil)
      }
    }

    private func makeClientWithDeferredDisconnect(delay: TimeInterval) -> RealtimeClientV2 {
      RealtimeClientV2(
        url: url,
        options: RealtimeClientOptions(
          headers: ["apikey": apiKey],
          disconnectOnEmptyChannelsAfter: delay
        ),
        wsTransport: { [client = self.client] _, _ in client },
        http: http,
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

extension WebSocketEvent {
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
