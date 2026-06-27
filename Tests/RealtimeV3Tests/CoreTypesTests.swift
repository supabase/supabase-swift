import Helpers
import Testing

@testable import RealtimeV3

@Suite struct CoreTypesTests {
  @Test func jsonValueIsAnyJSONAlias() {
    let v: JSONValue = .string("hi")
    #expect(v == AnyJSON.string("hi"))
  }

  @Test func channelStateEquatableAcrossCloseReason() {
    #expect(ChannelState.closed(.userRequested) == ChannelState.closed(.userRequested))
    #expect(ChannelState.closed(.userRequested) != ChannelState.closed(.timeout))
    #expect(ChannelState.joined == ChannelState.joined)
  }

  @Test func closeReasonServerClosedCarriesCodeAndMessage() {
    let a = CloseReason.serverClosed(code: 1011, message: "boom")
    let b = CloseReason.serverClosed(code: 1011, message: "boom")
    #expect(a == b)
  }
}
