import XCTest
@_spi(Internal) import _Helpers
import ConcurrencyExtras
import CustomDump

@testable import Realtime

final class RealtimeTests: XCTestCase {
  let url = URL(string: "https://localhost:54321/realtime/v1")!
  let apiKey = "anon.api.key"

  func testConnect() async {
    let mock = MockWebSocketClient()

    let realtime = Realtime(
      config: Realtime.Configuration(url: url, apiKey: apiKey),
      makeWebSocketClient: { _ in mock }
    )

    let connectTask = Task {
      await realtime.connect()
    }

    mock.continuation.yield(.open)

    await connectTask.value

    XCTAssertEqual(realtime.status, .connected)
  }

  func testChannelSubscription() async {
    let mock = MockWebSocketClient()

    let realtime = Realtime(
      config: Realtime.Configuration(url: url, apiKey: apiKey),
      makeWebSocketClient: { _ in mock }
    )

    let connectTask = Task {
      await realtime.connect()
    }

    mock.continuation.yield(.open)

    await connectTask.value

    let channel = realtime.channel("users")

    let (stream, continuation) = AsyncStream<Void>.makeStream()

    let receivedPostgresChanges: ActorIsolated<[PostgresAction]> = .init([])
    Task {
      continuation.yield()
      for await change in channel.postgresChange(filter: ChannelFilter(
        event: "*",
        table: "users"
      )) {
        await receivedPostgresChanges.withValue { $0.append(change) }
      }
    }

    // Use stream for awaiting until the `postgresChange` is called inside Task above, and call
    // subscribe only after that.
    await stream.first(where: { _ in true })
    await channel.subscribe()

    let receivedMessages = mock.messages

    XCTAssertNoDifference(
      receivedMessages,
      [
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
          ref: nil
        ),
      ]
    )

    let action = PostgresAction(
      columns: [Column(name: "email", type: "string")],
      commitTimestamp: 0,
      action: .delete(oldRecord: ["email": "mail@example.com"])
    )

    mock._receive?.resume(
      returning: _RealtimeMessage(
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
        ref: nil
      )
    )

    let receivedChanges = await receivedPostgresChanges.value
    XCTAssertNoDifference(receivedChanges, [action])
  }
}

class MockWebSocketClient: WebSocketClientProtocol {
  let status: AsyncStream<WebSocketClient.ConnectionStatus>
  let continuation: AsyncStream<WebSocketClient.ConnectionStatus>.Continuation

  init() {
    (status, continuation) = AsyncStream<WebSocketClient.ConnectionStatus>.makeStream()
  }

  var messages: [_RealtimeMessage] = []
  func send(_ message: _RealtimeMessage) async throws {
    messages.append(message)
  }

  var _receive: CheckedContinuation<_RealtimeMessage, Error>?
  func receive() async throws -> _RealtimeMessage? {
    try await withCheckedThrowingContinuation {
      _receive = $0
    }
  }

  func cancel() {}
}
