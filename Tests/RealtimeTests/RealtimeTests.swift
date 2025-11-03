import Clocks
import ConcurrencyExtras
import CustomDump
import InlineSnapshotTesting
import TestHelpers
@preconcurrency import XCTest

@testable import Realtime

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@MainActor
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

  override func setUp() async throws {
    try await super.setUp()

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
      wsTransport: { [client] _, _ in client! },
      http: http
    )
  }

  override func tearDown() async throws {
    sut.disconnect()

    try await super.tearDown()
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
      }
    }

    await sut.connect()

    XCTAssertEqual(socketStatuses.value, [.disconnected, .connecting, .connected])

    let messageTask = sut.messageTask
    XCTAssertNotNil(messageTask)

    let heartbeatTask = sut.heartbeatTask
    XCTAssertNotNil(heartbeatTask)

    let channelStatuses = LockIsolated([RealtimeChannelStatus]())
    channel.onStatusChange { status in
      channelStatuses.withValue {
        $0.append(status)
      }
    }
    .store(in: &subscriptions)

    let subscribeTask = Task {
      try await channel.subscribeWithError()
    }
    await Task.yield()
    server.send(.messagesSubscribed)

    // Wait until it subscribes to assert WS events
    do {
      try await subscribeTask.value
    } catch {
      XCTFail("Expected .subscribed but got error: \(error)")
    }
    XCTAssertEqual(channelStatuses.value, [.unsubscribed, .subscribing, .subscribed])

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

    let events = client.sentEvents.compactMap { $0.realtimeMessage }

    assertInlineSnapshot(of: events, as: .json, record: .failed) {
      #"""
      [
        {
          "event" : "heartbeat",
          "payload" : {

          },
          "ref" : "1",
          "topic" : "phoenix"
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
        },
        {
          "event" : "phx_join",
          "join_ref" : "3",
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
          "ref" : "3",
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

    let pendingHeartbeatRef = sut.pendingHeartbeatRef
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
    } return: { [sut] _ in
      HTTPResponse(
        data: "{}".data(using: .utf8)!,
        response: HTTPURLResponse(
          url: sut!.broadcastURL,
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

    XCTAssertEqual(sut.accessToken, validToken)
  }

  func testSetAuthWithNonJWT() async throws {
    let token = "sb-token"
    await sut.setAuth(token)
  }
}

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
