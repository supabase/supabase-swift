import _Helpers
import ConcurrencyExtras
import CustomDump
@testable import Realtime
import TestHelpers
import XCTest

final class RealtimeTests: XCTestCase {
  let url = URL(string: "https://localhost:54321/realtime/v1")!
  let apiKey = "anon.api.key"

  override func invokeTest() {
    withMainSerialExecutor {
      super.invokeTest()
    }
  }

  var ws: MockWebSocketClient!
  var sut: RealtimeClientV2!

  override func setUp() {
    super.setUp()

    ws = MockWebSocketClient()
    sut = RealtimeClientV2(
      config: RealtimeClientV2.Configuration(
        url: url,
        apiKey: apiKey,
        heartbeatInterval: 1,
        reconnectDelay: 1
      ),
      ws: ws
    )
  }

  func testBehavior() async {
    let channel = await sut.channel("public:messages")
    _ = await channel.postgresChange(InsertAction.self, table: "messages")
    _ = await channel.postgresChange(UpdateAction.self, table: "messages")
    _ = await channel.postgresChange(DeleteAction.self, table: "messages")

    let statusChange = await sut.statusChange

    await connectSocketAndWait()

    let status = await statusChange.prefix(3).collect()
    XCTAssertEqual(status, [.disconnected, .connecting, .connected])

    let messageTask = await sut.messageTask
    XCTAssertNotNil(messageTask)

    let heartbeatTask = await sut.heartbeatTask
    XCTAssertNotNil(heartbeatTask)

    let subscription = Task {
      await channel.subscribe()
    }
    await Task.megaYield()
    ws.mockReceive(.messagesSubscribed)

    // Wait until channel subscribed
    await subscription.value

    XCTAssertNoDifference(ws.sentMessages.value, [.subscribeToMessages])
  }

  func testHeartbeat() async throws {
    let expectation = expectation(description: "heartbeat")
    expectation.expectedFulfillmentCount = 2

    ws.on { message in
      if message.event == "heartbeat" {
        expectation.fulfill()
        return RealtimeMessageV2(
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

    let statuses = LockIsolated<[RealtimeClientV2.Status]>([])

    Task {
      for await status in await sut.statusChange {
        statuses.withValue {
          $0.append(status)
        }
      }
    }
    await Task.megaYield()
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

  private func connectSocketAndWait() async {
    let connection = Task {
      await sut.connect()
    }
    await Task.megaYield()

    ws.mockConnect(.connected)
    await connection.value
  }
}

extension RealtimeMessageV2 {
  static let subscribeToMessages = Self(
    joinRef: "1",
    ref: "1",
    topic: "realtime:public:messages",
    event: "phx_join",
    payload: [
      "access_token": "anon.api.key",
      "config": [
        "broadcast": [
          "self": false,
          "ack": false,
        ],
        "postgres_changes": [
          ["table": "messages", "event": "INSERT", "schema": "public"],
          ["table": "messages", "schema": "public", "event": "UPDATE"],
          ["schema": "public", "table": "messages", "event": "DELETE"],
        ],
        "presence": ["key": ""],
      ],
    ]
  )

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

  static let heartbeatResponse = Self(
    joinRef: nil,
    ref: "1",
    topic: "phoenix",
    event: "phx_reply",
    payload: [
      "response": [:],
      "status": "ok",
    ]
  )
}
