import Testing

@testable import Realtime

@Suite
struct RealtimeStatusTests {
  static let dropped = RealtimeError.socketClosed(code: .goingAway, reason: nil)

  @Test
  func clientStatusPredicates() {
    #expect(RealtimeClientStatus.connected.isConnected)
    #expect(RealtimeClientStatus.connected.error == nil)
    #expect(!RealtimeClientStatus.connecting(attempt: 1).isConnected)
    #expect(RealtimeClientStatus.connecting(attempt: 1).error == nil)
    #expect(RealtimeClientStatus.disconnected(nil).error == nil)
    #expect(
      RealtimeClientStatus.disconnected(Self.dropped).error?.isSameFailure(as: Self.dropped) == true
    )

    let reconnecting = RealtimeClientStatus.reconnecting(
      attempt: 1, retryIn: .seconds(1), lastError: Self.dropped)
    #expect(!reconnecting.isConnected)
    #expect(reconnecting.error?.isSameFailure(as: Self.dropped) == true)
  }

  @Test
  func channelStatusPredicates() {
    #expect(RealtimeChannelStatus.subscribed.isSubscribed)
    for status in [
      RealtimeChannelStatus.unsubscribed, .subscribing(attempt: 1), .unsubscribing,
    ] {
      #expect(!status.isSubscribed)
      #expect(status.error == nil)
    }

    let resubscribing = RealtimeChannelStatus.resubscribing(
      attempt: 1, retryIn: .seconds(1), lastError: Self.dropped)
    #expect(!resubscribing.isSubscribed)
    #expect(resubscribing.error?.isSameFailure(as: Self.dropped) == true)
    #expect(
      RealtimeChannelStatus.failed(Self.dropped).error?.isSameFailure(as: Self.dropped) == true)
  }

  @Test
  func channelStatusIsSameComparesCaseAndValues() {
    #expect(RealtimeChannelStatus.subscribing(attempt: 1).isSame(as: .subscribing(attempt: 1)))
    #expect(!RealtimeChannelStatus.subscribing(attempt: 1).isSame(as: .subscribing(attempt: 2)))
    #expect(!RealtimeChannelStatus.subscribed.isSame(as: .unsubscribed))
    #expect(RealtimeChannelStatus.failed(Self.dropped).isSame(as: .failed(Self.dropped)))
    #expect(!RealtimeChannelStatus.failed(Self.dropped).isSame(as: .failed(.notConnected)))
    #expect(
      RealtimeChannelStatus.resubscribing(attempt: 1, retryIn: .seconds(1), lastError: Self.dropped)
        .isSame(as: .resubscribing(attempt: 1, retryIn: .seconds(1), lastError: Self.dropped)))
    #expect(
      !RealtimeChannelStatus.resubscribing(
        attempt: 1, retryIn: .seconds(1), lastError: Self.dropped
      )
      .isSame(as: .resubscribing(attempt: 1, retryIn: .seconds(2), lastError: Self.dropped)))
  }
}
