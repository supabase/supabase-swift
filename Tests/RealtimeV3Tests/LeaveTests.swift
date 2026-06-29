//
//  LeaveTests.swift
//  RealtimeV3Tests
//
//  Created by Guilherme Souza on 29/06/26.
//

import ConcurrencyExtras
import Foundation
import Helpers
import Testing

@testable import RealtimeV3

@Suite struct LeaveTests {

  // MARK: - leaveClosesChannel

  /// Verifies that leave() transitions the channel to .closed(.userRequested).
  @Test func leaveClosesChannel() async throws {
    let (transport, server) = InMemoryTransport.pair()
    let rt = Realtime(url: URL(string: "wss://x")!, apiKey: "k", transport: transport)
    let channel = await rt.channel("room:1")

    server.autoReplyToJoins()
    server.autoReplyToLeaves()

    try await channel.subscribe()

    // Confirm joined state.
    let joinedState = await channel.state.first(where: { _ in true })
    #expect(joinedState == .joined)

    try await channel.leave()

    // Observe .closed(.userRequested) from state stream.
    let stateStream = await channel.state
    var last: ChannelState?
    var iterations = 0
    for await s in stateStream {
      last = s
      iterations += 1
      if case .closed(.userRequested) = s { break }
      if iterations > 20 { break }
    }
    if case .closed(.userRequested) = last {
      // expected
    } else {
      Issue.record("Expected .closed(.userRequested), got: \(String(describing: last))")
    }
  }

  // MARK: - resubscribeAfterLeaveWorks

  /// Verifies that a channel can be re-joined after a successful leave().
  @Test func resubscribeAfterLeaveWorks() async throws {
    let (transport, server) = InMemoryTransport.pair()
    let rt = Realtime(url: URL(string: "wss://x")!, apiKey: "k", transport: transport)
    let channel = await rt.channel("room:1")

    server.autoReplyToJoins()
    server.autoReplyToLeaves()

    // First subscribe.
    try await channel.subscribe()
    let joinedState = await channel.state.first(where: { _ in true })
    #expect(joinedState == .joined)

    // Leave.
    try await channel.leave()

    // Re-subscribe from .closed state.
    try await channel.subscribe()

    let resubState = await channel.state.first(where: { _ in true })
    #expect(resubState == .joined)
  }

  // MARK: - leaveIsIdempotent

  /// Verifies that calling leave() twice does not hang and leaves the channel .closed(.userRequested).
  @Test func leaveIsIdempotent() async throws {
    let (transport, server) = InMemoryTransport.pair()
    let rt = Realtime(url: URL(string: "wss://x")!, apiKey: "k", transport: transport)
    let channel = await rt.channel("room:1")

    server.autoReplyToJoins()
    server.autoReplyToLeaves()

    try await channel.subscribe()

    // First leave.
    try await channel.leave()

    // Second leave — should be a no-op, not hang.
    try await channel.leave()

    let finalState = await channel.state.first(where: { _ in true })
    if case .closed(.userRequested) = finalState {
      // expected
    } else {
      Issue.record(
        "Expected .closed(.userRequested) after second leave, got: \(String(describing: finalState))"
      )
    }
  }
}
