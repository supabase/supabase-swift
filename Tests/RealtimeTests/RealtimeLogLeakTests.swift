import Foundation
import Logging
import TestHelpers
import Testing

@testable import Realtime

@Suite
struct RealtimeLogLeakTests {
  private let recorder = LogRecorder()

  @Test
  func theClientLoggerRedactsTokens() throws {
    let client = try RealtimeClient(
      url: URL(string: "ws://localhost:54321/realtime/v1")!,
      options: RealtimeClientOptions(logger: recorder.makeLogger())
    )

    client.logger.error("rejoin failed: access_token=rt-secret-1")

    #expect(recorder.entries.contains { $0.contains("access_token=<redacted>") })
    #expect(!recorder.entries.contains { $0.contains("rt-secret") })
  }

  @Test
  func aMessageThatFailsToEncodeLogsNoPayload() async {
    let (fake, _) = FakeWebSocket.fakes()
    let outbox = Outbox(
      connection: fake, serializer: RealtimeSerializer(), logger: recorder.makeLogger())
    defer { outbox.close() }

    outbox.enqueue(
      RealtimeMessage(
        joinRef: "1", ref: "1", topic: "realtime:room", event: "access_token",
        payload: ["access_token": "rt-secret-2", "bad": .double(.nan)]))

    await waitUntil { !recorder.entries.isEmpty }
    #expect(recorder.entries.first?.contains("realtime:room") == true)
    #expect(!recorder.entries.contains { $0.contains("rt-secret") })
  }
}
