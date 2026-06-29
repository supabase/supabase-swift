//
//  SubscribeTests.swift
//  RealtimeV3Tests
//
//  Created by Guilherme Souza on 29/06/26.
//

import ConcurrencyExtras
import Foundation
import Helpers
import Testing

@testable import RealtimeV3

@Suite struct SubscribeTests {

  // MARK: - subscribeJoinsOnServerReply

  @Test func subscribeJoinsOnServerReply() async throws {
    let (transport, server) = InMemoryTransport.pair()
    let rt = Realtime(url: URL(string: "wss://x")!, apiKey: "k", transport: transport)
    let channel = await rt.channel("room:1")

    // Enable auto-reply BEFORE calling subscribe so the reply arrives without clock tricks.
    server.autoReplyToJoins()

    try await channel.subscribe()

    // Read the state stream until we reach .joined (or exhaust a bounded window).
    let stateStream = await channel.state
    var last: ChannelState?
    var iterations = 0
    for await s in stateStream {
      last = s
      iterations += 1
      if s == .joined { break }
      if iterations > 20 { break }
    }
    #expect(last == .joined)
  }

  // MARK: - secondSubscribeIsNoOp

  @Test func secondSubscribeIsNoOp() async throws {
    let (transport, server) = InMemoryTransport.pair()
    let rt = Realtime(url: URL(string: "wss://x")!, apiKey: "k", transport: transport)
    let channel = await rt.channel("room:1")

    let joinsSeen = LockIsolated(0)
    server.autoReplyToJoins(onJoin: { joinsSeen.withValue { $0 += 1 } })

    // First subscribe — should join.
    try await channel.subscribe()
    // The state stream is seeded with the current state; the first element should be .joined.
    let currentState = await channel.state.first(where: { _ in true })
    #expect(currentState == .joined)

    // Second subscribe — should be a no-op (no second join frame sent, returns immediately).
    try await channel.subscribe()

    // Give time for any spurious second join to arrive.
    try await Task.sleep(nanoseconds: 10_000_000)

    #expect(joinsSeen.value == 1)
  }

  // MARK: - subscribeRejectedThrows

  @Test func subscribeRejectedThrows() async throws {
    let (transport, server) = InMemoryTransport.pair()
    let rt = Realtime(url: URL(string: "wss://x")!, apiKey: "k", transport: transport)
    let channel = await rt.channel("room:2")

    server.autoReplyToJoins(
      status: "error",
      response: ["reason": "unauthorized"]
    )

    do {
      try await channel.subscribe()
      Issue.record("Expected subscribe() to throw channelJoinRejected, but it returned normally.")
    } catch {
      if case .channelJoinRejected = error {
        // Expected — test passes.
      } else {
        Issue.record("Expected channelJoinRejected, got: \(error)")
      }
    }
  }
}
