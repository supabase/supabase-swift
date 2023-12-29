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

  func testConnect() async throws {
    let mock = MockWebSocketClient()

    let realtime = Realtime(
      config: Realtime.Configuration(url: url, apiKey: apiKey, authTokenProvider: nil),
      makeWebSocketClient: { _ in mock }
    )

    let connectTask = Task {
      try await realtime.connect()
    }

    mock.statusContinuation?.yield(.open)

    try await connectTask.value

    XCTAssertEqual(realtime.status, .connected)
  }

  func testChannelSubscription() async throws {
    let mock = MockWebSocketClient()

    let realtime = Realtime(
      config: Realtime.Configuration(url: url, apiKey: apiKey, authTokenProvider: nil),
      makeWebSocketClient: { _ in mock }
    )

    let connectTask = Task {
      try await realtime.connect()
    }
    await Task.megaYield()

    mock.statusContinuation?.yield(.open)

    try await connectTask.value

    let channel = realtime.channel("users")

    let changes = channel.postgresChange(
      AnyAction.self,
      table: "users"
    )

    try await channel.subscribe()

    let receivedPostgresChanges: ActorIsolated<[any PostgresAction]> = .init([])
    Task {
      for await change in changes {
        await receivedPostgresChanges.withValue { $0.append(change) }
      }
    }

    let receivedMessages = mock.messages

    XCTAssertNoDifference(
      receivedMessages,
      try [
        RealtimeMessageV2(
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
        ),
      ]
    )

    mock.receiveContinuation?.yield(
      RealtimeMessageV2(
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
        ]
      )
    )

    let currentDate = Date()

    let action = DeleteAction(
      columns: [Column(name: "email", type: "string")],
      commitTimestamp: currentDate,
      oldRecord: ["email": "mail@example.com"]
    )

    try mock.receiveContinuation?.yield(
      RealtimeMessageV2(
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
    )

    await Task.megaYield()

    let receivedChanges = await receivedPostgresChanges.value
    XCTAssertNoDifference(receivedChanges as? [DeleteAction], [action])
  }
}

class MockWebSocketClient: WebSocketClientProtocol {
  func connect() async -> AsyncThrowingStream<WebSocketClient.ConnectionStatus, Error> {
    let (stream, continuation) = AsyncThrowingStream<WebSocketClient.ConnectionStatus, Error>
      .makeStream()
    statusContinuation = continuation
    return stream
  }

  var statusContinuation: AsyncThrowingStream<WebSocketClient.ConnectionStatus, Error>.Continuation?

  var messages: [RealtimeMessageV2] = []
  func send(_ message: RealtimeMessageV2) async throws {
    messages.append(message)
  }

  var receiveStream: AsyncThrowingStream<RealtimeMessageV2, Error>?
  var receiveContinuation: AsyncThrowingStream<RealtimeMessageV2, Error>.Continuation?
  func receive() async -> AsyncThrowingStream<RealtimeMessageV2, Error> {
    let (stream, continuation) = AsyncThrowingStream<RealtimeMessageV2, Error>.makeStream()
    receiveStream = stream
    receiveContinuation = continuation
    return stream
  }

  func cancel() async {
    statusContinuation?.finish()
    receiveContinuation?.finish()
  }
}
