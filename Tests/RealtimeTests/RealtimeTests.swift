import XCTest
@_spi(Internal) import _Helpers
import ConcurrencyExtras
import CustomDump
@testable import Realtime

final class RealtimeTests: XCTestCase {
  let url = URL(string: "https://localhost:54321/realtime/v1")!
  let apiKey = "anon.api.key"
  let accessToken =
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJhdWQiOiJhdXRoZW50aWNhdGVkIiwiZXhwIjoxNzA1Nzc4MTAxLCJpYXQiOjE3MDU3NzQ1MDEsImlzcyI6Imh0dHA6Ly8xMjcuMC4wLjE6NTQzMjEvYXV0aC92MSIsInN1YiI6ImFiZTQ1NjMwLTM0YTAtNDBhNS04Zjg5LTQxY2NkYzJjNjQyNCIsImVtYWlsIjoib2dyc291emErbWFjQGdtYWlsLmNvbSIsInBob25lIjoiIiwiYXBwX21ldGFkYXRhIjp7InByb3ZpZGVyIjoiZW1haWwiLCJwcm92aWRlcnMiOlsiZW1haWwiXX0sInVzZXJfbWV0YWRhdGEiOnt9LCJyb2xlIjoiYXV0aGVudGljYXRlZCIsImFhbCI6ImFhbDEiLCJhbXIiOlt7Im1ldGhvZCI6Im1hZ2ljbGluayIsInRpbWVzdGFtcCI6MTcwNTYwODcxOX1dLCJzZXNzaW9uX2lkIjoiMzFmMmQ4NGQtODZmYi00NWE2LTljMTItODMyYzkwYTgyODJjIn0.RY1y5U7CK97v6buOgJj_jQNDHW_1o0THbNP2UQM1HVE"

  var ref: Int = 0
  func makeRef() -> String {
    ref += 1
    return "\(ref)"
  }

  func testConnectAndSubscribe() async {
    var mock = WebSocketClient.mock
    mock.status = .init(unfolding: { .open })
    mock.connect = {}
    mock.cancel = {}

    mock.receive = {
      .init {
        RealtimeMessageV2.messagesSubscribed
      }
    }

    var sentMessages: [RealtimeMessageV2] = []
    mock.send = { sentMessages.append($0) }

    let realtime = RealtimeClientV2(
      config: RealtimeClientV2.Configuration(url: url, apiKey: apiKey),
      makeWebSocketClient: { _, _ in mock }
    )

    XCTAssertNoLeak(realtime)

    let channel = await realtime.channel("public:messages")
    _ = await channel.postgresChange(InsertAction.self, table: "messages")
    _ = await channel.postgresChange(UpdateAction.self, table: "messages")
    _ = await channel.postgresChange(DeleteAction.self, table: "messages")

    let statusChange = await realtime.statusChange

    await realtime.connect()
    await realtime.setAuth(accessToken)

    let status = await statusChange.prefix(3).collect()
    XCTAssertEqual(status, [.disconnected, .connecting, .connected])

    let messageTask = await realtime.messageTask
    XCTAssertNotNil(messageTask)

    let heartbeatTask = await realtime.heartbeatTask
    XCTAssertNotNil(heartbeatTask)

    await channel.subscribe()

    XCTAssertNoDifference(sentMessages, [.subscribeToMessages])

    await realtime.disconnect()
  }

  func testHeartbeat() {
    // TODO: test heartbeat behavior
  }
}

extension AsyncSequence {
  func collect() async rethrows -> [Element] {
    try await reduce(into: [Element]()) { $0.append($1) }
  }
}

extension RealtimeMessageV2 {
  static let subscribeToMessages = Self(
    joinRef: "1",
    ref: "1",
    topic: "realtime:public:messages",
    event: "phx_join",
    payload: [
      "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJhdWQiOiJhdXRoZW50aWNhdGVkIiwiZXhwIjoxNzA1Nzc4MTAxLCJpYXQiOjE3MDU3NzQ1MDEsImlzcyI6Imh0dHA6Ly8xMjcuMC4wLjE6NTQzMjEvYXV0aC92MSIsInN1YiI6ImFiZTQ1NjMwLTM0YTAtNDBhNS04Zjg5LTQxY2NkYzJjNjQyNCIsImVtYWlsIjoib2dyc291emErbWFjQGdtYWlsLmNvbSIsInBob25lIjoiIiwiYXBwX21ldGFkYXRhIjp7InByb3ZpZGVyIjoiZW1haWwiLCJwcm92aWRlcnMiOlsiZW1haWwiXX0sInVzZXJfbWV0YWRhdGEiOnt9LCJyb2xlIjoiYXV0aGVudGljYXRlZCIsImFhbCI6ImFhbDEiLCJhbXIiOlt7Im1ldGhvZCI6Im1hZ2ljbGluayIsInRpbWVzdGFtcCI6MTcwNTYwODcxOX1dLCJzZXNzaW9uX2lkIjoiMzFmMmQ4NGQtODZmYi00NWE2LTljMTItODMyYzkwYTgyODJjIn0.RY1y5U7CK97v6buOgJj_jQNDHW_1o0THbNP2UQM1HVE",
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
