import Foundation
import Testing

@testable import RealtimeV3

@Suite struct PhoenixMessageTests {
  @Test func constructsBroadcastFrame() {
    let msg = PhoenixMessage(
      joinRef: "1", ref: nil, topic: "room:1", event: "broadcast",
      payload: .json(["x": 1]), receivedAt: Date(timeIntervalSince1970: 0)
    )
    #expect(msg.event == "broadcast")
    if case .json(let v) = msg.payload {
      #expect(v.objectValue?["x"] == 1)
    } else {
      Issue.record("expected json")
    }
  }
}
