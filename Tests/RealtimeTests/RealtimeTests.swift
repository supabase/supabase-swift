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
      url: url,
      options: RealtimeClientOptions(
        headers: ["apikey": apiKey],
        heartbeatInterval: 1,
        reconnectDelay: 1,
        timeoutInterval: 2,
        logger: TestLogger()
      ),
      ws: ws
    )
  }

  override func tearDown() async throws {
    await sut.disconnect()

    try await super.tearDown()
  }

  func testBehavior() async throws {
    try await withTimeout(interval: 2) { [self] in
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

      XCTAssertNoDifference(ws.sentMessages.value, [.subscribeToMessages(ref: "1", joinRef: "1")])
    }
  }

  func testSubscribeTimeout() async throws {
    let channel = await sut.channel("public:messages")
    let joinEventCount = LockIsolated(0)

    ws.on { message in
      if message.event == "heartbeat" {
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

    Task {
      await channel.subscribe()
    }

    await Task.megaYield()

    try? await Task.sleep(nanoseconds: NSEC_PER_SEC * 2)

    let joinSentMessages = ws.sentMessages.value.filter { $0.event == "phx_join" }

    let expectedMessages = try [
      RealtimeMessageV2(
        joinRef: "1",
        ref: "1",
        topic: "realtime:public:messages",
        event: "phx_join",
        payload: JSONObject(
          RealtimeJoinPayload(
            config: RealtimeJoinConfig(),
            accessToken: apiKey
          )
        )
      ),
      RealtimeMessageV2(
        joinRef: "3",
        ref: "3",
        topic: "realtime:public:messages",
        event: "phx_join",
        payload: JSONObject(
          RealtimeJoinPayload(
            config: RealtimeJoinConfig(),
            accessToken: apiKey
          )
        )
      ),
    ]

    XCTAssertNoDifference(
      joinSentMessages,
      expectedMessages
    )
  }

  func testHeartbeat() async throws {
    try await withTimeout(interval: 4) { [self] in
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
  }

  func testHeartbeat_whenNoResponse_shouldReconnect() async throws {
    try await withTimeout(interval: 6) { [self] in
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
  }

  func testChannelSubscribe_timeout() async throws {
    let channel = await sut.channel("test")
    await connectSocketAndWait()

    Task {
      await channel.subscribe()
    }

    await Task.megaYield()

    try? await Task.sleep(nanoseconds: NSEC_PER_SEC * 2)

    let joinMessages = ws.sentMessages.value.filter { $0.event == "phx_join" }

    XCTAssertNoDifference(
      joinMessages,
      [
        RealtimeMessageV2(
          joinRef: "1",
          ref: "1",
          topic: "realtime:test",
          event: "phx_join",
          payload: try JSONObject(
            RealtimeJoinPayload(
              config: RealtimeJoinConfig(),
              accessToken: apiKey
            )
          )
        ),
        RealtimeMessageV2(
          joinRef: "3",
          ref: "3",
          topic: "realtime:test",
          event: "phx_join",
          payload: try JSONObject(
            RealtimeJoinPayload(
              config: RealtimeJoinConfig(),
              accessToken: apiKey
            )
          )
        ),
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
  static func subscribeToMessages(ref: String?, joinRef: String?) -> RealtimeMessageV2 {
    Self(
      joinRef: joinRef,
      ref: ref,
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
  }

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

struct TestLogger: SupabaseLogger {
  func log(message: SupabaseLogMessage) {
    print(message.description)
  }
}
