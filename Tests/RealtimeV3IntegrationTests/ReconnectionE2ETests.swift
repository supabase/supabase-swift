//
//  ReconnectionE2ETests.swift
//  RealtimeV3IntegrationTests
//
//  Created by Guilherme Souza on 29/06/26.
//

import Foundation
import RealtimeV3
import Testing

/// IE-6: Reconnection e2e tests against a live local Supabase instance.
///
/// ## Scope and rationale
///
/// Forcing a genuine transport-level socket drop from the client side (without
/// restarting the Supabase server or killing the OS-level socket) is not possible
/// via the public `Realtime` API — `disconnect()` is an intentional/clean close,
/// not a network fault.
///
/// Deterministic reconnect + rejoin behaviour (after unclean transport drops) is
/// therefore covered by the unit test suite (`RealtimeV3Tests/RejoinTests`), which
/// uses an `InMemoryTransport` that can simulate unclean closes at will.
///
/// ## SDK gap — intentional disconnect + reconnect channel state
///
/// After `disconnect()`, channel states remain `.joined` in the SDK (the transport
/// is closed but the logical channel state is preserved for transparent reconnection
/// on unclean drops). Calling `connect()` re-establishes the socket but does NOT
/// trigger channel rejoins — `intentionalDisconnect = true` suppresses the reconnect
/// loop. Callers that want to reuse a channel after an intentional disconnect must
/// call `channel.leave()` first, then `channel.subscribe()` after `connect()`.
///
/// The live tests below exercise the leave → reconnect → re-subscribe cycle as the
/// supported pattern, and document the gap above.
///
/// Tests are automatically skipped when the instance is not reachable.
@Suite("IE-6 Reconnection", .requiresLocalSupabase)
struct ReconnectionE2ETests {

  // MARK: - IE-6a: leave + disconnect + connect + subscribe cycle

  @Test("channel rejoins after leave → disconnect → connect → subscribe")
  func channelRejoinsAfterLeaveDisconnectReconnect() async throws {
    let rt = IntegrationEnv.makeRealtime()
    let channel = await rt.channel("room:e2e-reconnect")

    // First subscribe cycle.
    try await channel.subscribe()
    let state1 = await channel.state
    try await waitFor(state1, timeout: .seconds(10), description: "channel joined (first)") {
      $0 == .joined
    }

    // Clean leave before disconnect so the channel reaches .closed.
    try await channel.leave()
    let state2 = await channel.state
    try await waitFor(state2, timeout: .seconds(5), description: "channel closed after leave") {
      if case .closed = $0 { return true }
      return false
    }

    // Intentional disconnect.
    await rt.disconnect()

    // Reconnect and re-subscribe.
    try await channel.subscribe()
    let state3 = await channel.state
    try await waitFor(
      state3, timeout: .seconds(10), description: "channel re-joined after reconnect"
    ) {
      $0 == .joined
    }

    // Clean up.
    try await channel.leave()
    await rt.disconnect()
  }

  // MARK: - IE-6b: broadcast stream after leave + reconnect cycle

  // Note: forced-drop reconnection (simulating network failure mid-stream without
  // intentional disconnect) is covered deterministically by `RealtimeV3Tests/RejoinTests`
  // using InMemoryTransport.
  //
  // SDK gap: after `disconnect()` without a prior `leave()`, the channel state stays
  // `.joined` and `subscribe()` is idempotent (returns immediately). Callers must
  // call `leave()` before `disconnect()` to allow re-subscription after `connect()`.

  @Test("broadcast stream delivers messages after leave → disconnect → connect → subscribe")
  func broadcastStreamResumesAfterReconnect() async throws {
    struct Ping: Codable, Sendable, Equatable { let seq: Int }

    let rtSender = IntegrationEnv.makeRealtime()
    let rtReceiver = IntegrationEnv.makeRealtime()

    let channelR = await rtReceiver.channel("room:e2e-reconnect-bcast")
    let channelS = await rtSender.channel("room:e2e-reconnect-bcast")

    try await channelR.subscribe()
    try await channelS.subscribe()

    let stateR1 = await channelR.state
    let stateS = await channelS.state
    try await waitFor(stateR1, timeout: .seconds(10), description: "receiver joined (first)") {
      $0 == .joined
    }
    try await waitFor(stateS, timeout: .seconds(10), description: "sender joined") {
      $0 == .joined
    }

    // Verify the channel works pre-disconnect.
    let preStream = await channelR.broadcasts(of: Ping.self, event: "ping")
    try await channelS.broadcast(Ping(seq: 1), as: "ping")

    var firstPing: Ping?
    try await withThrowingTaskGroup(of: Ping?.self) { group in
      group.addTask {
        for try await p in preStream { return p }
        return nil
      }
      group.addTask {
        try await Task.sleep(for: .seconds(10))
        throw TimeoutError(
          description: "receiver did not get pre-disconnect ping",
          timeout: .seconds(10)
        )
      }
      firstPing = try await group.next()!
      group.cancelAll()
    }
    #expect(firstPing == Ping(seq: 1))

    // Leave and disconnect receiver cleanly.
    // Note: leave() is required before disconnect() to clear the channel's .joined state
    // and allow re-subscription after connect() (see SDK gap note in the suite header).
    try await channelR.leave()
    let stateR2 = await channelR.state
    try await waitFor(stateR2, timeout: .seconds(5), description: "receiver closed after leave") {
      if case .closed = $0 { return true }
      return false
    }
    await rtReceiver.disconnect()

    // Reconnect receiver and re-subscribe.
    try await channelR.subscribe()
    let stateR3 = await channelR.state
    try await waitFor(stateR3, timeout: .seconds(10), description: "receiver re-joined") {
      $0 == .joined
    }

    // Open a fresh broadcast stream after reconnect and verify delivery.
    let postStream = await channelR.broadcasts(of: Ping.self, event: "ping")
    try await channelS.broadcast(Ping(seq: 2), as: "ping")

    var secondPing: Ping?
    try await withThrowingTaskGroup(of: Ping?.self) { group in
      group.addTask {
        for try await p in postStream { return p }
        return nil
      }
      group.addTask {
        try await Task.sleep(for: .seconds(10))
        throw TimeoutError(
          description: "receiver did not get post-reconnect ping",
          timeout: .seconds(10)
        )
      }
      secondPing = try await group.next()!
      group.cancelAll()
    }
    #expect(secondPing == Ping(seq: 2))

    try await channelR.leave()
    try await channelS.leave()
    await rtReceiver.disconnect()
    await rtSender.disconnect()
  }
}
