import XCTest
@_spi(Internal) import _Helpers
import ConcurrencyExtras
import CustomDump
@testable import Realtime

final class RealtimeTests: XCTestCase {
  let url = URL(string: "https://localhost:54321/realtime/v1")!
  let apiKey = "anon.api.key"

  var ref: Int = 0
  func makeRef() -> String {
    ref += 1
    return "\(ref)"
  }

  func testConnect() async {
    let mock = MockWebSocketClient()

    let realtime = RealtimeClientV2(
      config: RealtimeClientV2.Configuration(url: url, apiKey: apiKey),
      makeWebSocketClient: { _, _ in mock }
    )

//      XCTAssertNoLeak(realtime)

    Task {
      await realtime.connect()
    }

    mock.mockStatus(.open)

    await Task.megaYield()

    let status = await realtime.status
    XCTAssertEqual(status, .connected)
  }

  func testChannelSubscription() async throws {
    let mock = MockWebSocketClient()

    let realtime = RealtimeClientV2(
      config: RealtimeClientV2.Configuration(url: url, apiKey: apiKey),
      makeWebSocketClient: { _, _ in mock }
    )

    let channel = await realtime.channel("users")

    let changes = await channel.postgresChange(
      AnyAction.self,
      table: "users"
    )

    let task = Task {
      await channel.subscribe()
    }

    mock.mockStatus(.open)

    await Task.megaYield()

    await task.value

    let receivedPostgresChangeTask = Task {
      await changes
        .compactMap { $0.wrappedAction as? DeleteAction }
        .first { _ in true }
    }

    let sentMessages = mock.mutableState.sentMessages
    let expectedJoinMessage = try RealtimeMessageV2(
      joinRef: nil,
      ref: makeRef(),
      topic: "realtime:users",
      event: "phx_join",
      payload: [
        "config": AnyJSON(
          RealtimeJoinConfig(
            postgresChanges: [
              .init(event: .all, schema: "public", table: "users", filter: nil),
            ]
          )
        ),
      ]
    )

    XCTAssertNoDifference(sentMessages, [expectedJoinMessage])

    let currentDate = Date(timeIntervalSince1970: 725552399)

    let deleteActionRawMessage = try RealtimeMessageV2(
      joinRef: nil,
      ref: makeRef(),
      topic: "realtime:users",
      event: "postgres_changes",
      payload: [
        "data": AnyJSON(
          PostgresActionData(
            type: "DELETE",
            record: nil,
            oldRecord: ["email": "mail@example.com"],
            columns: [
              Column(name: "email", type: "string"),
            ],
            commitTimestamp: currentDate
          )
        ),
        "ids": [0],
      ]
    )

    let action = DeleteAction(
      columns: [Column(name: "email", type: "string")],
      commitTimestamp: currentDate,
      oldRecord: ["email": "mail@example.com"],
      rawMessage: deleteActionRawMessage
    )

    let postgresChangeReply = RealtimeMessageV2(
      joinRef: nil,
      ref: makeRef(),
      topic: "realtime:users",
      event: "phx_reply",
      payload: [
        "response": [
          "postgres_changes": [
            [
              "schema": "public",
              "table": "users",
              "filter": nil,
              "event": "*",
              "id": 0,
            ],
          ],
        ],
        "status": "ok",
      ]
    )

    mock.mockReceive(postgresChangeReply)
    mock.mockReceive(deleteActionRawMessage)

    let receivedChange = await receivedPostgresChangeTask.value
    XCTAssertNoDifference(receivedChange, action)

    await channel.unsubscribe()

    mock.mockReceive(
      RealtimeMessageV2(
        joinRef: nil,
        ref: nil,
        topic: "realtime:users",
        event: ChannelEvent.leave,
        payload: [:]
      )
    )

    await Task.megaYield()
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
