import Clocks
import ConcurrencyExtras
import Foundation
import Helpers
import TestHelpers
import Testing

@testable import Realtime

@Suite
struct RealtimeDisconnectTests {
  private func connectedClient() async throws -> (RealtimeClient, FakeWebSocket) {
    let (socket, _) = FakeWebSocket.fakes()
    let client = RealtimeClient(
      configuration: RealtimeClient.Configuration(
        url: URL(string: "http://localhost:54321/realtime/v1")!,
        observesAppLifecycle: false),
      wsTransport: { _, _ in socket },
      http: HTTPClient(transport: RecordingTransport()),
      clock: TestClock()
    )
    try await client.connect()
    return (client, socket)
  }

  @Test
  func disconnectSendsTheGivenCloseCodeAndReason() async throws {
    let (client, socket) = try await connectedClient()

    await client.disconnect(code: .goingAway, reason: "bye")

    #expect(socket.closeCode == WebSocketCloseCode.goingAway.rawValue)
    #expect(socket.closeReason == "bye")
  }

  @Test
  func disconnectWithoutACodeSendsANormalClosure() async throws {
    let (client, socket) = try await connectedClient()

    await client.disconnect()

    #expect(socket.closeCode == WebSocketCloseCode.normalClosure.rawValue)
  }
}
