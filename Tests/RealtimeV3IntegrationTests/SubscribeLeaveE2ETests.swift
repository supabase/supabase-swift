//
//  SubscribeLeaveE2ETests.swift
//  RealtimeV3IntegrationTests
//
//  Created by Guilherme Souza on 29/06/26.
//

import Foundation
import RealtimeV3
import Testing

/// IE-2: Channel subscribe/leave e2e tests against a live local Supabase instance.
///
/// These tests require a running local Supabase stack:
///   cd Tests/RealtimeV3IntegrationTests/supabase && supabase start
///
/// They are automatically skipped when the instance is not reachable.
@Suite("IE-2 Subscribe and Leave", .requiresLocalSupabase)
struct SubscribeLeaveE2ETests {

  // MARK: - IE-2a: subscribe -> joined -> leave -> closed(.userRequested)

  @Test("subscribes to a public broadcast channel and leaves cleanly")
  func subscribeAndLeavePublicChannel() async throws {
    let rt = IntegrationEnv.makeRealtime()

    // channel() automatically prepends "realtime:" — pass the short topic here.
    let channel = await rt.channel("room:1")
    let stateStream = await channel.state

    // subscribe() auto-connects the socket and joins the channel
    try await channel.subscribe()

    // Observe channel reaches .joined
    try await waitFor(
      stateStream,
      timeout: .seconds(10),
      description: "channel state == .joined"
    ) { state in
      state == .joined
    }

    // Leave the channel
    try await channel.leave()

    // Observe channel reaches .closed(.userRequested)
    let postLeaveStream = await channel.state
    try await waitFor(
      postLeaveStream,
      timeout: .seconds(5),
      description: "channel state == .closed(.userRequested)"
    ) { state in
      if case .closed(.userRequested) = state { return true }
      return false
    }

    await rt.disconnect()
  }

  // MARK: - IE-2b: subscribe to a realtime:public:messages topic

  @Test("subscribes to a public:messages topic (SDK adds realtime: prefix)")
  func subscribeToRealtimeTopic() async throws {
    let rt = IntegrationEnv.makeRealtime()

    // The canonical Supabase realtime topic for postgres-changes on a table.
    // channel() prepends "realtime:" — pass the short form "public:messages".
    let channel = await rt.channel("public:messages")
    let stateStream = await channel.state

    try await channel.subscribe()

    try await waitFor(
      stateStream,
      timeout: .seconds(10),
      description: "realtime:public:messages channel state == .joined"
    ) { state in
      state == .joined
    }

    try await channel.leave()

    let postLeaveStream = await channel.state
    try await waitFor(
      postLeaveStream,
      timeout: .seconds(5),
      description: "realtime:public:messages channel state == .closed"
    ) { state in
      if case .closed = state { return true }
      return false
    }

    await rt.disconnect()
  }

  // MARK: - IE-2c: first-call-wins channel identity

  @Test("subscribing to the same topic returns the pre-existing channel (first-call-wins)")
  func subscribeToSameTopicIsIdempotent() async throws {
    let rt = IntegrationEnv.makeRealtime()

    let ch1 = await rt.channel("room:idempotent")
    let ch2 = await rt.channel("room:idempotent")

    // Both references must point to the same actor identity
    #expect(ch1 === ch2)

    try await ch1.subscribe()

    let stateStream = await ch1.state
    try await waitFor(
      stateStream,
      timeout: .seconds(10),
      description: "idempotent channel state == .joined"
    ) { state in
      state == .joined
    }

    try await ch1.leave()
    await rt.disconnect()
  }
}
