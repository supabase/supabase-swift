//
//  RealtimeClientTests.swift
//  _Realtime
//
//  Created by Guilherme Souza on 24/04/25.
//

import Clocks
import ConcurrencyExtras
import Foundation
import Testing

@testable import _Realtime

@Suite struct RealtimeClientTests {
  static let testURL = URL(string: "ws://localhost:4000/realtime/v1")!

  @Test func connectTransitionsToConnected() async throws {
    let (transport, _) = InMemoryTransport.pair()
    let realtime = Realtime(
      url: Self.testURL,
      apiKey: .literal("anon-key"),
      transport: transport
    )

    try await realtime.connect()
    let snapshot = await realtime.currentStatus
    #expect(snapshot == .connected)
  }

  @Test func disconnectTransitionsToClosed() async throws {
    let clock = TestClock()
    let (transport, _) = InMemoryTransport.pair()
    let config = Configuration { $0.clock = clock }
    let realtime = Realtime(
      url: Self.testURL,
      apiKey: .literal("key"),
      configuration: config,
      transport: transport
    )

    try await realtime.connect()
    await realtime.disconnect()

    let snapshot = await realtime.currentStatus
    #expect(snapshot == .closed(.userRequested))
  }

  @Test func channelSameTopicReturnsSameActor() async throws {
    let (transport, _) = InMemoryTransport.pair()
    let realtime = Realtime(url: Self.testURL, apiKey: .literal("key"), transport: transport)

    let ch1 = await realtime.channel("room:1")
    let ch2 = await realtime.channel("room:1")
    #expect(ch1 === ch2)
  }

  @Test func channelDifferentTopicsReturnDifferentActors() async throws {
    let (transport, _) = InMemoryTransport.pair()
    let realtime = Realtime(url: Self.testURL, apiKey: .literal("key"), transport: transport)

    let ch1 = await realtime.channel("room:1")
    let ch2 = await realtime.channel("room:2")
    #expect(ch1 !== ch2)
  }
}
