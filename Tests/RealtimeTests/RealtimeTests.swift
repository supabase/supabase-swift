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

    mock.statusContinuation.yield(.open)

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

    mock.statusContinuation.yield(.open)

    try await connectTask.value

    let channel = realtime.channel("users")

    let changes = channel.postgresChange(
      filter: ChannelFilter(
        event: "*",
        table: "users"
      )
    )

    try await channel.subscribe()

    let receivedPostgresChanges: ActorIsolated<[PostgresAction]> = .init([])
    Task {
      for await change in changes {
        await receivedPostgresChanges.withValue { $0.append(change) }
      }
    }

    let receivedMessages = mock.messages

    XCTAssertNoDifference(
      receivedMessages,
      try [
        _RealtimeMessage(
          topic: "realtime:users",
          event: "phx_join",
          payload: AnyJSON(
            RealtimeJoinConfig(
              postgresChanges: [
                .init(schema: "public", table: "users", filter: nil, event: "*"),
              ]
            )
          ).objectValue ?? [:],
          ref: makeRef()
        ),
      ]
    )

    mock.receiveContinuation?.yield(
      _RealtimeMessage(
        topic: "realtime:users",
        event: "phx_reply",
        payload: [
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
        ref: makeRef()
      )
    )

    let action = PostgresAction(
      columns: [Column(name: "email", type: "string")],
      commitTimestamp: 0,
      action: .delete(oldRecord: ["email": "mail@example.com"])
    )

    try mock.receiveContinuation?.yield(
      _RealtimeMessage(
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
              commitTimestamp: 0
            )
          ),
          "ids": [0],
        ],
        ref: makeRef()
      )
    )

    await Task.megaYield()

    let receivedChanges = await receivedPostgresChanges.value
    XCTAssertNoDifference(receivedChanges, [action])
  }
}

class MockWebSocketClient: WebSocketClientProtocol {
  var status: AsyncThrowingStream<WebSocketClient.ConnectionStatus, Error>
  let statusContinuation: AsyncThrowingStream<WebSocketClient.ConnectionStatus, Error>.Continuation

  func connect() {}

  init() {
    (status, statusContinuation) = AsyncThrowingStream<WebSocketClient.ConnectionStatus, Error>
      .makeStream()
  }

  var messages: [_RealtimeMessage] = []
  func send(_ message: _RealtimeMessage) async throws {
    messages.append(message)
  }

  var receiveStream: AsyncThrowingStream<_RealtimeMessage, Error>?
  var receiveContinuation: AsyncThrowingStream<_RealtimeMessage, Error>.Continuation?
  func receive() -> AsyncThrowingStream<_RealtimeMessage, Error> {
    let (stream, continuation) = AsyncThrowingStream<_RealtimeMessage, Error>.makeStream()
    receiveStream = stream
    receiveContinuation = continuation
    return stream
  }

  func cancel() {
    statusContinuation.finish()
    receiveContinuation?.finish()
  }
}
