import Clocks
import ConcurrencyExtras
import CustomDump
import Helpers
import InlineSnapshotTesting
import TestHelpers
import XCTest

@testable import Realtime

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
final class RealtimeTests: XCTestCase {
  let url = URL(string: "https://localhost:54321/realtime/v1")!
  let apiKey = "anon.api.key"

  override func invokeTest() {
    withMainSerialExecutor {
      super.invokeTest()
    }
  }

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
      wsTransport: { self.client },
      http: http
    )
  }

  override func tearDown() {
    sut.disconnect()

    super.tearDown()
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

    await sut.connect()

    XCTAssertEqual(socketStatuses.value, [.disconnected, .connecting, .connected])

    let messageTask = sut.mutableState.messageTask
    XCTAssertNotNil(messageTask)

    let heartbeatTask = sut.mutableState.heartbeatTask
    XCTAssertNotNil(heartbeatTask)

    let channelStatuses = LockIsolated([RealtimeChannelStatus]())
    channel.onStatusChange { status in
      channelStatuses.withValue {
        $0.append(status)
      }
    }
    .store(in: &subscriptions)

    let subscribeTask = Task {
      await channel.subscribe()
    }
    await Task.yield()
    server.send(.messagesSubscribed)

    // Wait until it subscribes to assert WS events
    await subscribeTask.value

    XCTAssertEqual(channelStatuses.value, [.unsubscribed, .subscribing, .subscribed])

    assertInlineSnapshot(of: client.sentEvents.map(\.json), as: .json) {
      """
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
                  "key" : ""
                },
                "private" : false
              }
            },
            "ref" : "1",
            "topic" : "realtime:public:messages"
          }
        }
      ]
      """
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
      await channel.subscribe()
    }

    // Wait for the timeout for rejoining.
    await testClock.advance(by: .seconds(timeoutInterval))

    let events = client.sentEvents.compactMap { $0.realtimeMessage }.filter {
      $0.event == "phx_join"
    }
    assertInlineSnapshot(of: events, as: .json) {
      """
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
                "key" : ""
              },
              "private" : false
            }
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
                "key" : ""
              },
              "private" : false
            }
          },
          "ref" : "2",
          "topic" : "realtime:public:messages"
        }
      ]
      """
    }
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

    await sut.connect()

    await testClock.advance(by: .seconds(heartbeatInterval * 2))

    await fulfillment(of: [expectation], timeout: 3)
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
    assertInlineSnapshot(of: request?.urlRequest, as: .raw(pretty: true)) {
      """
      POST https://localhost:54321/realtime/v1/api/broadcast
      Authorization: Bearer custom.access.token
      Content-Type: application/json
      apiKey: anon.api.key

      {
        "messages" : [
          {
            "event" : "test",
            "payload" : {
              "value" : 42
            },
            "private" : false,
            "topic" : "realtime:public:messages"
          }
        ]
      }
      """
    }
  }

  func testSetAuth() async {
    let validToken =
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyLCJleHAiOjY0MDkyMjExMjAwfQ.GfiEKLl36X8YWcatHg31jRbilovlGecfUKnOyXMSX9c"
    await sut.setAuth(validToken)

    XCTAssertEqual(sut.mutableState.accessToken, validToken)
  }

  func testSetAuthWithExpiredToken() async throws {
    let expiredToken =
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyLCJleHAiOi02NDA5MjIxMTIwMH0.tnbZRC8vEyK3zaxPxfOjNgvpnuum18dxYlXeHJ4r7u8"
    await sut.setAuth(expiredToken)

    XCTAssertNotEqual(sut.mutableState.accessToken, expiredToken)
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
