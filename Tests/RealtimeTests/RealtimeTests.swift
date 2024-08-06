import ConcurrencyExtras
import CustomDump
import Helpers
import InlineSnapshotTesting
@testable import Realtime
import TestHelpers
import XCTest

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

  var ws: MockWebSocketClient!
  var http: HTTPClientMock!
  var sut: RealtimeClient!

  override func setUp() {
    super.setUp()

    ws = MockWebSocketClient()
    http = HTTPClientMock()
    sut = RealtimeClient(
      url: url,
      options: RealtimeClientOptions(
        headers: ["apikey": apiKey],
        heartbeatInterval: 1,
        reconnectDelay: 1,
        timeoutInterval: 2,
        logger: TestLogger()
      ),
      ws: ws,
      http: http
    )
  }

  override func tearDown() async throws {
    await sut.disconnect()
    try await super.tearDown()
  }

  func testBehavior() async throws {
    let channel = await sut.channel("public:messages")
    var subscriptions: Set<ObservationToken> = []

    await channel.onPostgresChange(InsertAction.self, table: "messages") { _ in
    }
    .store(in: &subscriptions)

    await channel.onPostgresChange(UpdateAction.self, table: "messages") { _ in
    }
    .store(in: &subscriptions)

    await channel.onPostgresChange(DeleteAction.self, table: "messages") { _ in
    }
    .store(in: &subscriptions)

    let socketStatuses = LockIsolated([RealtimeClient.Status]())

    await sut.onStatusChange { status in
      socketStatuses.withValue { $0.append(status) }
    }
    .store(in: &subscriptions)

    await connectSocketAndWait()

    XCTAssertEqual(socketStatuses.value, [.disconnected, .connecting, .connected])

    let messageTask = await sut.messageTask
    XCTAssertNotNil(messageTask)

    let heartbeatTask = await sut.heartbeatTask
    XCTAssertNotNil(heartbeatTask)

    let channelStatuses = LockIsolated([RealtimeChannel.Status]())
    await channel.onStatusChange { status in
      channelStatuses.withValue {
        $0.append(status)
      }
    }
    .store(in: &subscriptions)

    ws.mockReceive(.messagesSubscribed)
    await channel.subscribe()

    assertInlineSnapshot(of: ws.sentMessages, as: .json) {
      """
      [
        {
          "event" : "phx_join",
          "join_ref" : "1",
          "payload" : {
            "access_token" : "anon.api.key",
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
      ]
      """
    }
  }

  func testSubscribeTimeout() async throws {
    let channel = await sut.channel("public:messages")
    let joinEventCount = LockIsolated(0)

    ws.on { message in
      if message.event == "heartbeat" {
        return RealtimeMessage(
          joinRef: message.joinRef,
          ref: message.ref,
          topic: "phoenix",
          event: "phx_reply",
          payload: [
            "response": [:],
            "status": "ok",
          ]
        )
      }

      if message.event == "phx_join" {
        joinEventCount.withValue { $0 += 1 }

        // Skip first join.
        if joinEventCount.value == 2 {
          return .messagesSubscribed
        }
      }

      return nil
    }

    await connectSocketAndWait()
    await channel.subscribe()

    try? await Task.sleep(nanoseconds: NSEC_PER_SEC * 2)

    let joinSentMessages = ws.sentMessages.filter { $0.event == "phx_join" }

    assertInlineSnapshot(of: joinSentMessages, as: .json) {
      """
      [
        {
          "event" : "phx_join",
          "join_ref" : "1",
          "payload" : {
            "access_token" : "anon.api.key",
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
          "join_ref" : "3",
          "payload" : {
            "access_token" : "anon.api.key",
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
          "ref" : "3",
          "topic" : "realtime:public:messages"
        }
      ]
      """
    }
  }

  func testHeartbeat() async throws {
    let expectation = expectation(description: "heartbeat")
    expectation.expectedFulfillmentCount = 2

    ws.on { message in
      if message.event == "heartbeat" {
        expectation.fulfill()
        return RealtimeMessage(
          joinRef: message.joinRef,
          ref: message.ref,
          topic: "phoenix",
          event: "phx_reply",
          payload: [
            "response": [:],
            "status": "ok",
          ]
        )
      }

      return nil
    }

    await connectSocketAndWait()

    await fulfillment(of: [expectation], timeout: 3)
  }

  func testHeartbeat_whenNoResponse_shouldReconnect() async throws {
    let sentHeartbeatExpectation = expectation(description: "sentHeartbeat")

    ws.on {
      if $0.event == "heartbeat" {
        sentHeartbeatExpectation.fulfill()
      }

      return nil
    }

    let statuses = LockIsolated<[RealtimeClient.Status]>([])

    Task {
      for await status in await sut.statusChange {
        statuses.withValue {
          $0.append(status)
        }
      }
    }
    await Task.yield()
    await connectSocketAndWait()

    await fulfillment(of: [sentHeartbeatExpectation], timeout: 2)

    let pendingHeartbeatRef = await sut.pendingHeartbeatRef
    XCTAssertNotNil(pendingHeartbeatRef)

    // Wait until next heartbeat
    try await Task.sleep(nanoseconds: NSEC_PER_SEC * 2)

    // Wait for reconnect delay
    try await Task.sleep(nanoseconds: NSEC_PER_SEC * 1)

    XCTAssertEqual(
      statuses.value,
      [
        .disconnected,
        .connecting,
        .connected,
        .disconnected,
        .connecting,
      ]
    )
  }

  func testBroadcastWithHTTP() async throws {
    await http.when {
      $0.url.path.hasSuffix("broadcast")
    } return: { _ in
      await HTTPResponse(
        data: "{}".data(using: .utf8)!,
        response: HTTPURLResponse(
          url: self.sut.broadcastURL,
          statusCode: 200,
          httpVersion: nil,
          headerFields: nil
        )!
      )
    }

    let channel = await sut.channel("public:messages") {
      $0.broadcast.acknowledgeBroadcasts = true
    }

    try await channel.broadcast(event: "test", message: ["value": 42])

    let request = await http.receivedRequests.last
    expectNoDifference(
      request?.headers,
      [
        "content-type": "application/json",
        "apikey": "anon.api.key",
        "authorization": "Bearer anon.api.key",
      ]
    )

    let body = try XCTUnwrap(request?.body)
    let json = try JSONDecoder().decode(JSONObject.self, from: body)

    assertInlineSnapshot(of: json, as: .json) {
      """
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

  private func connectSocketAndWait() async {
    ws.mockConnect(.connected)
    await sut.connect()
  }
}

extension RealtimeMessage {
  static let messagesSubscribed = Self(
    joinRef: nil,
    ref: "2",
    topic: "realtime:public:messages",
    event: "phx_reply",
    payload: [
      "response": [
        "postgres_changes": [
          ["id": 43783255, "event": "INSERT", "schema": "public", "table": "messages"],
          ["id": 124973000, "event": "UPDATE", "schema": "public", "table": "messages"],
          ["id": 85243397, "event": "DELETE", "schema": "public", "table": "messages"],
        ],
      ],
      "status": "ok",
    ]
  )
}

struct TestLogger: SupabaseLogger {
  func log(message: SupabaseLogMessage) {
    print(message.description)
  }
}
