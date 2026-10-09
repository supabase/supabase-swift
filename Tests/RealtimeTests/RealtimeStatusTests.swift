//
//  RealtimeStatusTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 08/10/26.
//

import Testing

@testable import Realtime

@Suite
struct RealtimeStatusTests {
  static let lost = RealtimeError(kind: .transport, message: "lost")

  @Test(
    arguments: [
      (RealtimeConnectionStatus.disconnected(nil), false, nil),
      (.disconnected(lost), false, "lost"),
      (.connecting(attempt: 1), false, nil),
      (.connected, true, nil),
      (.reconnecting(attempt: 2, retryIn: .seconds(1), lastError: lost), false, "lost"),
    ] as [(RealtimeConnectionStatus, Bool, String?)])
  func connectionPredicates(
    status: RealtimeConnectionStatus, isConnected: Bool, errorMessage: String?
  ) {
    #expect(status.isConnected == isConnected)
    #expect(status.error?.message == errorMessage)
  }

  @Test(
    arguments: [
      (RealtimeChannelStatus.unsubscribed, false, nil),
      (.subscribing(attempt: 1), false, nil),
      (.subscribed, true, nil),
      (.resubscribing(attempt: 2, retryIn: .seconds(1), lastError: lost), false, "lost"),
      (.unsubscribing, false, nil),
      (.failed(lost), false, "lost"),
    ] as [(RealtimeChannelStatus, Bool, String?)])
  func channelPredicates(
    status: RealtimeChannelStatus, isSubscribed: Bool, errorMessage: String?
  ) {
    #expect(status.isSubscribed == isSubscribed)
    #expect(status.error?.message == errorMessage)
  }

  @Test
  func channelPublicStatusDropsIsRejoin() {
    let status = ChannelMachine.State.subscribing(attempt: 2, isRejoin: true).publicStatus
    guard case .subscribing(attempt: 2) = status else {
      Issue.record("expected .subscribing(attempt: 2), got \(status)")
      return
    }
  }

  @Test
  func connectionPublicStatusKeepsTheRetryDetails() {
    let status = ConnectionMachine.State.reconnecting(
      attempt: 3, retryIn: .seconds(4), lastError: Self.lost
    ).publicStatus
    guard case .reconnecting(attempt: 3, retryIn: .seconds(4), let error) = status else {
      Issue.record("expected .reconnecting(attempt: 3, retryIn: 4s), got \(status)")
      return
    }
    #expect(error.message == "lost")
  }
}
