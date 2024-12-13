import ConcurrencyExtras
import CustomDump
import Helpers
import InlineSnapshotTesting
import TestHelpers
import WebSocket
import XCTest

@testable import Realtime

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

final class RealtimeTests: XCTestCase {
  let url = URL(string: "https://localhost:54321/realtime/v1")!
  let apiKey = "anon.api.key"

  override func invokeTest() {
    withMainSerialExecutor {
      super.invokeTest()
    }
  }

  var ws: FakeWebSocket!
  var http: HTTPClientMock!
  var sut: RealtimeClientV2!

  override func setUp() {
    super.setUp()

    let (client, server) = FakeWebSocket.fakes()
    ws = server
    http = HTTPClientMock()
    sut = RealtimeClientV2(
      url: url,
      options: RealtimeClientOptions(
        headers: ["apikey": apiKey],
        heartbeatInterval: 1,
        reconnectDelay: 1,
        timeoutInterval: 2,
        accessToken: {
          "custom.access.token"
        }
      ),
      wsFactory: { _, _ in client },
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

    let heartbeatTask = sut.mutableState.heartbeatTask
    XCTAssertNotNil(heartbeatTask)

    let channelStatuses = LockIsolated([RealtimeChannelStatus]())
    channel.onStatusChange { status in
      channelStatuses.withValue {
        $0.append(status)
      }
    }
    .store(in: &subscriptions)

    try ws.send(binary: JSONEncoder().encode(RealtimeMessageV2.messagesSubscribed))
    await channel.subscribe()
    //
    //    assertInlineSnapshot(of: ws.sentMessages, as: .json) {
    //      """
    //      [
    //        {
    //          "event" : "phx_join",
    //          "join_ref" : "1",
    //          "payload" : {
    //            "access_token" : "custom.access.token",
    //            "config" : {
    //              "broadcast" : {
    //                "ack" : false,
    //                "self" : false
    //              },
    //              "postgres_changes" : [
    //                {
    //                  "event" : "INSERT",
    //                  "schema" : "public",
    //                  "table" : "messages"
    //                },
    //                {
    //                  "event" : "UPDATE",
    //                  "schema" : "public",
    //                  "table" : "messages"
    //                },
    //                {
    //                  "event" : "DELETE",
    //                  "schema" : "public",
    //                  "table" : "messages"
    //                }
    //              ],
    //              "presence" : {
    //                "key" : ""
    //              },
    //              "private" : false
    //            }
    //          },
    //          "ref" : "1",
    //          "topic" : "realtime:public:messages"
    //        }
    //      ]
    //      """
    //    }
  }

  func testSubscribeTimeout() async throws {
    let channel = sut.channel("public:messages")
    let joinEventCount = LockIsolated(0)

    let receivedEvents = LockIsolated([WebSocketEvent]())
    ws.onEvent = { @Sendable [weak self] event in
      receivedEvents.withValue { $0.append(event) }

      guard let msg = RealtimeMessageV2(event: event) else { return }

      if msg.event == "heartbeat" {
        self?.ws.send(
          text: """
            {
              "join_ref": "\(msg.joinRef ?? "")",
              "ref": "\(msg.ref ?? "")",
              "topic": "phoenix",
              "event": "phx_reply",
              "payload": {
                "response": {},
                "status": "ok"
              }
            }
            """
        )
      }

      if msg.event == "phx_join" {
        joinEventCount.withValue { $0 += 1 }

        // Skip first join.
        if joinEventCount.value == 2 {
          self?.ws.send(
            text: """
              {
                "join_ref": nil,
                "ref": "2",
                "topic": "realtime:public:messages",
                "event": "phx_reply",
                "payload": {
                  "response": {
                    "postgres_changes": {
                      {"id": 43_783_255, "event": "INSERT", "schema": "public", "table": "messages"},
                      {"id": 124_973_000, "event": "UPDATE", "schema": "public", "table": "messages"},
                      {"id": 85_243_397, "event": "DELETE", "schema": "public", "table": "messages"},
                    }
                  },
                  "status": "ok",
                }
              }
              """
          )
        }
      }
    }

    await sut.connect()
    await channel.subscribe()

    try? await Task.sleep(nanoseconds: NSEC_PER_SEC * 2)

    assertInlineSnapshot(of: receivedEvents.value, as: .dump)
  }

//  func testHeartbeat() async throws {
//    let expectation = expectation(description: "heartbeat")
//    expectation.expectedFulfillmentCount = 2
//
//    ws.on { message in
//      if message.event == "heartbeat" {
//        expectation.fulfill()
//        return RealtimeMessageV2(
//          joinRef: message.joinRef,
//          ref: message.ref,
//          topic: "phoenix",
//          event: "phx_reply",
//          payload: [
//            "response": [:],
//            "status": "ok",
//          ]
//        )
//      }
//
//      return nil
//    }
//
//    await sut.connect()
//
//    await fulfillment(of: [expectation], timeout: 3)
//  }

//  func testHeartbeat_whenNoResponse_shouldReconnect() async throws {
//    let sentHeartbeatExpectation = expectation(description: "sentHeartbeat")
//
//    ws.on {
//      if $0.event == "heartbeat" {
//        sentHeartbeatExpectation.fulfill()
//      }
//
//      return nil
//    }
//
//    let statuses = LockIsolated<[RealtimeClientStatus]>([])
//
//    Task {
//      for await status in sut.statusChange {
//        statuses.withValue {
//          $0.append(status)
//        }
//      }
//    }
//    await Task.yield()
//    await sut.connect()
//
//    await fulfillment(of: [sentHeartbeatExpectation], timeout: 2)
//
//    let pendingHeartbeatRef = sut.mutableState.pendingHeartbeatRef
//    XCTAssertNotNil(pendingHeartbeatRef)
//
//    // Wait until next heartbeat
//    try await Task.sleep(nanoseconds: NSEC_PER_SEC * 2)
//
//    // Wait for reconnect delay
//    try await Task.sleep(nanoseconds: NSEC_PER_SEC * 1)
//
//    XCTAssertEqual(
//      statuses.value,
//      [
//        .disconnected,
//        .connecting,
//        .connected,
//        .disconnected,
//        .connecting,
//      ]
//    )
//  }

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

  //  private func connectSocketAndWait() async {
  //    ws.mockConnect(.connected)
  //    await sut.connect()
  //  }
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

extension RealtimeMessageV2 {
  init?(event: WebSocketEvent) {
    switch event {
    case .binary(let data):
      if let msg = try? JSONDecoder().decode(RealtimeMessageV2.self, from: data) {
        self = msg
      } else {
        return nil
      }
    case .text(let text):
      if let msg = try? JSONDecoder().decode(RealtimeMessageV2.self, from: Data(text.utf8)) {
        self = msg
      } else {
        return nil
      }
    case .close:
      return nil
    }
  }
}
