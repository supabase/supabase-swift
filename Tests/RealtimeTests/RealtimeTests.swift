import Clocks
import ConcurrencyExtras
import CustomDump
import Foundation
import InlineSnapshotTesting
import TestHelpers
import XCTest

@testable import Realtime

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

#if os(Linux)
  @available(*, unavailable, message: "RealtimeTests are disabled on Linux due to timing flakiness")
  final class RealtimeTests: XCTestCase {}
#else

  @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
  final class RealtimeTests: XCTestCase {
    let url = URL(string: "http://localhost:54321/realtime/v1")!
    let apiKey = "anon.api.key"

    #if !os(Windows) && !os(Linux) && !os(Android)
      override func invokeTest() {
        withMainSerialExecutor {
          super.invokeTest()
        }
      }
    #endif

    var server: FakeWebSocket!
    var client: FakeWebSocket!
    var http: HTTPClientMock!
    var sut: RealtimeClientV2!
    var testClock: TestClock<Duration>!

    let heartbeatInterval: TimeInterval = RealtimeClientOptions.defaultHeartbeatInterval
    let reconnectDelay: TimeInterval = RealtimeClientOptions.defaultReconnectDelay
    let timeoutInterval: TimeInterval = RealtimeClientOptions.defaultTimeoutInterval

    override func setUp() {
      super.setUp()

      (client, server) = FakeWebSocket.fakes()
      http = HTTPClientMock()
      testClock = TestClock()
      _clock = testClock

      sut = RealtimeClientV2(
        url: url,
        options: RealtimeClientOptions(
          headers: ["apikey": apiKey],
          accessToken: {
            "custom.access.token"
          }
        ),
        wsTransport: { _, _ in self.client },
        http: http
      )
    }

    override func tearDown() {
      sut.disconnect()

      super.tearDown()
    }

    func test_transport() async {
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
            ws://localhost:54321/realtime/v1/websocket?apikey=anon.api.key&vsn=1.0.0&log_level=warn
            """
          }
          return FakeWebSocket.fakes().0
        },
        http: http
      )

      await client.connect()
    }

    func testBehavior() async throws {
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

      // Set up server to respond to heartbeats
      server.onEvent = { @Sendable [server] event in
        guard let msg = event.realtimeMessage else { return }

        if msg.event == "heartbeat" {
          server?.send(
            RealtimeMessageV2(
              joinRef: msg.joinRef,
              ref: msg.ref,
              topic: "phoenix",
              event: "phx_reply",
              payload: ["response": [:]]
            )
          )
        } else if msg.event == "phx_join" {
          server?.send(.messagesSubscribed)
        }
      }

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
        XCTFail("Expected .subscribed but got error: \(error)")
      }
      XCTAssertEqual(channelStatuses.value, [.unsubscribed, .subscribing, .subscribed])

      XCTAssertEqual(
        Array(socketStatuses.value.prefix(3)),
        [.disconnected, .connecting, .connected]
      )

      let messageTask = sut.mutableState.messageTask
      XCTAssertNotNil(messageTask)

      let heartbeatTask = sut.mutableState.heartbeatTask
      XCTAssertNotNil(heartbeatTask)

      assertInlineSnapshot(of: client.sentEvents.map(\.json), as: .json) {
        #"""
        [
          {
            "text" : {
              "event" : "phx_join",
              "join_ref" : "1",
              "payload" : {
                "access_token" : "custom.access.token",
                "config" : {
                  "broadcast" : {
                    "ack" : false,
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
              },
              "ref" : "1",
              "topic" : "realtime:public:messages"
            }
          }
        ]
        """#
      }
    }

    func testSubscribeTimeout() async throws {
      let channel = sut.channel("public:messages")
      let joinEventCount = LockIsolated(0)

      server.onEvent = { @Sendable [server] event in
        guard let msg = event.realtimeMessage else { return }

        if msg.event == "heartbeat" {
          server?.send(
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
            server?.send(.messagesSubscribed)
          }
        }
      }

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

    // Succeeds after 2 retries (on 3rd attempt)
    func testSubscribeTimeout_successAfterRetries() async throws {
      let successAttempt = 3
      let channel = sut.channel("public:messages")
      let joinEventCount = LockIsolated(0)

      server.onEvent = { @Sendable [server] event in
        guard let msg = event.realtimeMessage else { return }

        if msg.event == "heartbeat" {
          server?.send(
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
            server?.send(.messagesSubscribed)
          }
        }
      }

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

      XCTAssertEqual(events.count, successAttempt)
      XCTAssertEqual(channel.status, .subscribed)
    }

    // Fails after max retries (should unsubscribe)
    func testSubscribeTimeout_failsAfterMaxRetries() async throws {
      let channel = sut.channel("public:messages")
      let joinEventCount = LockIsolated(0)

      server.onEvent = { @Sendable [server] event in
        guard let msg = event.realtimeMessage else { return }
        if msg.event == "heartbeat" {
          server?.send(
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
        XCTFail("Expected error but got success")
      } catch {
        XCTAssertTrue(error is RealtimeError)
      }

      let events = client.sentEvents.compactMap { $0.realtimeMessage }.filter {
        $0.event == "phx_join"
      }
      XCTAssertEqual(events.count, 5)
      XCTAssertEqual(channel.status, .unsubscribed)
    }

    // Cancels and unsubscribes if the subscribe task is cancelled
    func testSubscribeTimeout_cancelsOnTaskCancel() async throws {
      let channel = sut.channel("public:messages")
      let joinEventCount = LockIsolated(0)

      server.onEvent = { @Sendable [server] event in
        guard let msg = event.realtimeMessage else { return }
        if msg.event == "heartbeat" {
          server?.send(
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

      await sut.connect()
      await testClock.advance(by: .seconds(heartbeatInterval))

      let subscribeTask = Task {
        try await channel.subscribeWithError()
      }

      await testClock.advance(by: .seconds(timeoutInterval))
      subscribeTask.cancel()

      do {
        try await subscribeTask.value
        XCTFail("Expected cancellation error but got success")
      } catch is CancellationError {
        // Expected
      } catch {
        XCTFail("Expected CancellationError but got: \(error)")
      }
      await testClock.advance(by: .seconds(5.0))

      let events = client.sentEvents.compactMap { $0.realtimeMessage }.filter {
        $0.event == "phx_join"
      }

      XCTAssertEqual(events.count, 1)
      XCTAssertEqual(channel.status, .unsubscribed)
    }

    func testHeartbeat() async throws {
      let expectation = expectation(description: "heartbeat")
      expectation.expectedFulfillmentCount = 2

      server.onEvent = { @Sendable [server] event in
        guard let msg = event.realtimeMessage else { return }

        if msg.event == "heartbeat" {
          expectation.fulfill()
          server?.send(
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

      let heartbeatStatuses = LockIsolated<[HeartbeatStatus]>([])
      let subscription = sut.onHeartbeat { status in
        heartbeatStatuses.withValue {
          $0.append(status)
        }
      }
      defer { subscription.cancel() }

      await sut.connect()

      await testClock.advance(by: .seconds(heartbeatInterval * 2))

      await fulfillment(of: [expectation], timeout: 3)

      expectNoDifference(heartbeatStatuses.value, [.sent, .ok, .sent, .ok])
    }

    func testHeartbeat_whenNoResponse_shouldReconnect() async throws {
      let sentHeartbeatExpectation = expectation(description: "sentHeartbeat")

      server.onEvent = { @Sendable in
        if $0.realtimeMessage?.event == "heartbeat" {
          sentHeartbeatExpectation.fulfill()
        }
      }

      let statuses = LockIsolated<[RealtimeClientStatus]>([])
      let subscription = sut.onStatusChange { status in
        statuses.withValue {
          $0.append(status)
        }
      }
      defer { subscription.cancel() }

      await sut.connect()
      await testClock.advance(by: .seconds(heartbeatInterval))

      await fulfillment(of: [sentHeartbeatExpectation], timeout: 0)

      let pendingHeartbeatRef = sut.mutableState.pendingHeartbeatRef
      XCTAssertNotNil(pendingHeartbeatRef)

      // Wait until next heartbeat
      await testClock.advance(by: .seconds(heartbeatInterval))

      // Wait for reconnect delay
      await testClock.advance(by: .seconds(reconnectDelay))

      XCTAssertEqual(
        statuses.value,
        [
          .disconnected,
          .connecting,
          .connected,
          .disconnected,
          .connecting,
          .connected,
        ]
      )
    }

    func testHeartbeat_timeout() async throws {
      let heartbeatStatuses = LockIsolated<[HeartbeatStatus]>([])
      let s1 = sut.onHeartbeat { status in
        heartbeatStatuses.withValue {
          $0.append(status)
        }
      }
      defer { s1.cancel() }

      // Don't respond to any heartbeats
      server.onEvent = { _ in }

      await sut.connect()
      await testClock.advance(by: .seconds(heartbeatInterval))

      // First heartbeat sent
      XCTAssertEqual(heartbeatStatuses.value, [.sent])

      // Wait for timeout
      await testClock.advance(by: .seconds(timeoutInterval))

      // Wait for next heartbeat.
      await testClock.advance(by: .seconds(heartbeatInterval))

      // Should have timeout status
      XCTAssertEqual(heartbeatStatuses.value, [.sent, .timeout])
    }

    func testBroadcastWithHTTP() async throws {
      await http.when {
        $0.url.path.hasSuffix("broadcast")
      } return: { _ in
        HTTPResponse(
          data: "{}".data(using: .utf8)!,
          response: HTTPURLResponse(
            url: self.sut.broadcastURL,
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
        	--header "apiKey: anon.api.key" \
        	--data "{\"messages\":[{\"event\":\"test\",\"payload\":{\"value\":42},\"private\":false,\"topic\":\"realtime:public:messages\"}]}" \
        	"http://localhost:54321/realtime/v1/api/broadcast"
        """#
      }
    }

    func testSetAuth() async {
      let validToken =
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyLCJleHAiOjY0MDkyMjExMjAwfQ.GfiEKLl36X8YWcatHg31jRbilovlGecfUKnOyXMSX9c"
      await sut.setAuth(validToken)

      XCTAssertEqual(sut.mutableState.accessToken, validToken)
    }

    func testSetAuthWithNonJWT() async throws {
      let token = "sb-token"
      await sut.setAuth(token)
    }

    // MARK: - Task Lifecycle Tests

    func testListenForMessagesCancelsExistingTask() async {
      server.onEvent = { @Sendable [server] event in
        guard let msg = event.realtimeMessage else { return }

        if msg.event == "heartbeat" {
          server?.send(
            RealtimeMessageV2(
              joinRef: msg.joinRef,
              ref: msg.ref,
              topic: "phoenix",
              event: "phx_reply",
              payload: ["response": [:]]
            )
          )
        }
      }

      await sut.connect()

      // Get the first message task
      let firstMessageTask = sut.mutableState.messageTask
      XCTAssertNotNil(firstMessageTask)
      XCTAssertFalse(firstMessageTask?.isCancelled ?? true)

      // Trigger reconnection which will call listenForMessages again
      sut.disconnect()
      await sut.connect()

      // Verify the old task was cancelled
      XCTAssertTrue(firstMessageTask?.isCancelled ?? false)

      // Verify a new task was created
      let secondMessageTask = sut.mutableState.messageTask
      XCTAssertNotNil(secondMessageTask)
      XCTAssertFalse(secondMessageTask?.isCancelled ?? true)
    }

    func testStartHeartbeatingCancelsExistingTask() async {
      server.onEvent = { @Sendable [server] event in
        guard let msg = event.realtimeMessage else { return }

        if msg.event == "heartbeat" {
          server?.send(
            RealtimeMessageV2(
              joinRef: msg.joinRef,
              ref: msg.ref,
              topic: "phoenix",
              event: "phx_reply",
              payload: ["response": [:]]
            )
          )
        }
      }

      await sut.connect()

      // Get the first heartbeat task
      let firstHeartbeatTask = sut.mutableState.heartbeatTask
      XCTAssertNotNil(firstHeartbeatTask)
      XCTAssertFalse(firstHeartbeatTask?.isCancelled ?? true)

      // Trigger reconnection which will call startHeartbeating again
      sut.disconnect()
      await sut.connect()

      // Verify the old task was cancelled
      XCTAssertTrue(firstHeartbeatTask?.isCancelled ?? false)

      // Verify a new task was created
      let secondHeartbeatTask = sut.mutableState.heartbeatTask
      XCTAssertNotNil(secondHeartbeatTask)
      XCTAssertFalse(secondHeartbeatTask?.isCancelled ?? true)
    }

    func testMessageProcessingRespectsCancellation() async {
      let messagesProcessed = LockIsolated(0)

      server.onEvent = { @Sendable [server] event in
        guard let msg = event.realtimeMessage else { return }

        if msg.event == "heartbeat" {
          server?.send(
            RealtimeMessageV2(
              joinRef: msg.joinRef,
              ref: msg.ref,
              topic: "phoenix",
              event: "phx_reply",
              payload: ["response": [:]]
            )
          )
        }
      }

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
	  XCTAssertNil(sut.mutableState.messageTask, "Message task should be nil after disconnect")
    }

    func testMultipleReconnectionsHandleTaskLifecycleCorrectly() async {
      server.onEvent = { @Sendable [server] event in
        guard let msg = event.realtimeMessage else { return }

        if msg.event == "heartbeat" {
          server?.send(
            RealtimeMessageV2(
              joinRef: msg.joinRef,
              ref: msg.ref,
              topic: "phoenix",
              event: "phx_reply",
              payload: ["response": [:]]
            )
          )
        }
      }

      var previousMessageTasks: [Task<Void, Never>?] = []
      var previousHeartbeatTasks: [Task<Void, Never>?] = []

      // Test multiple connect/disconnect cycles
      for _ in 1...3 {
        await sut.connect()

        await waitUntil { [sut = self.sut!] in
          let messageTask = sut.mutableState.messageTask
          let heartbeatTask = sut.mutableState.heartbeatTask
          return messageTask != nil
            && heartbeatTask != nil
            && !(messageTask?.isCancelled ?? true)
            && !(heartbeatTask?.isCancelled ?? true)
        }

        let messageTask = sut.mutableState.messageTask
        let heartbeatTask = sut.mutableState.heartbeatTask

        XCTAssertNotNil(messageTask)
        XCTAssertNotNil(heartbeatTask)
        XCTAssertFalse(messageTask?.isCancelled ?? true)
        XCTAssertFalse(heartbeatTask?.isCancelled ?? true)

        previousMessageTasks.append(messageTask)
        previousHeartbeatTasks.append(heartbeatTask)

        sut.disconnect()

        await waitUntil {
          (messageTask?.isCancelled ?? false) && (heartbeatTask?.isCancelled ?? false)
        }

        // Verify tasks were cancelled after disconnect
        XCTAssertTrue(messageTask?.isCancelled ?? false)
        XCTAssertTrue(heartbeatTask?.isCancelled ?? false)
      }

      // Verify all previous tasks were properly cancelled
      for task in previousMessageTasks {
        await waitUntil { task?.isCancelled ?? false }
        XCTAssertTrue(task?.isCancelled ?? false)
      }

      for task in previousHeartbeatTasks {
        await waitUntil { task?.isCancelled ?? false }
        XCTAssertTrue(task?.isCancelled ?? false)
      }
    }

    func waitUntil(
      timeout: TimeInterval = 1.0,
      pollInterval: UInt64 = 10_000_000,
      condition: @escaping @Sendable () -> Bool
    ) async {
      let deadline = Date().addingTimeInterval(timeout)

      while Date() < deadline {
        if condition() { return }
        try? await Task.sleep(nanoseconds: pollInterval)
      }
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
    try! self.send(String(decoding: JSONEncoder().encode(message), as: UTF8.self))
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
    return try? JSONDecoder().decode(RealtimeMessageV2.self, from: Data(text.utf8))
  }
}
