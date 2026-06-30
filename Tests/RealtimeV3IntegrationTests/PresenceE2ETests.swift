//
//  PresenceE2ETests.swift
//  RealtimeV3IntegrationTests
//
//  Created by Guilherme Souza on 29/06/26.
//

import Foundation
import RealtimeV3
import Testing

// MARK: - Shared fixture

private struct UserPresence: Codable, Sendable, Equatable {
  let userId: String
  let status: String
}

/// IE-4: Presence e2e tests against a live local Supabase instance.
///
/// These tests require a running local Supabase stack:
///   cd Tests/RealtimeV3IntegrationTests/supabase && supabase start
///
/// They are automatically skipped when the instance is not reachable.
@Suite("IE-4 Presence", .requiresLocalSupabase)
struct PresenceE2ETests {

  // MARK: - IE-4a: presence sync between two clients

  @Test("presence state from A is visible to B, and A's leave removes it")
  func presenceSyncBetweenTwoClients() async throws {
    let rtA = IntegrationEnv.makeRealtime()
    let rtB = IntegrationEnv.makeRealtime()

    // Both clients join the same topic with presence enabled.
    let channelA = await rtA.channel("room:e2e-presence") {
      $0.presence.enabled = true
    }
    let channelB = await rtB.channel("room:e2e-presence") {
      $0.presence.enabled = true
    }

    // Register B's observer stream before subscribe so no event is lost.
    let presenceStream = await channelB.presence.observe(UserPresence.self)

    // Subscribe A first, then B.
    try await channelA.subscribe()
    let stateA = await channelA.state
    try await waitFor(stateA, timeout: .seconds(10), description: "channelA joined (presence)") {
      $0 == .joined
    }

    try await channelB.subscribe()
    let stateB = await channelB.state
    try await waitFor(stateB, timeout: .seconds(10), description: "channelB joined (presence)") {
      $0 == .joined
    }

    // A tracks its presence.
    let handle = try await channelA.presence.track(
      UserPresence(userId: "user-a", status: "active")
    )

    // Wait until B sees A in the active map.
    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask {
        for await state in presenceStream {
          let userIds = state.active.values.flatMap { $0 }.map(\.userId)
          if userIds.contains("user-a") { return }
        }
      }
      group.addTask {
        try await Task.sleep(for: .seconds(10))
        throw TimeoutError(
          description: "B did not see A in presence within timeout",
          timeout: .seconds(10)
        )
      }
      try await group.next()
      group.cancelAll()
    }

    // A untrack: cancel the handle.
    try await handle.cancel()

    // B should see A leave — active map should no longer contain "user-a".
    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask {
        for await state in presenceStream {
          let userIds = state.active.values.flatMap { $0 }.map(\.userId)
          if !userIds.contains("user-a") { return }
        }
      }
      group.addTask {
        try await Task.sleep(for: .seconds(10))
        throw TimeoutError(
          description: "B did not see A leave presence within timeout",
          timeout: .seconds(10)
        )
      }
      try await group.next()
      group.cancelAll()
    }

    try await channelA.leave()
    try await channelB.leave()
    await rtA.disconnect()
    await rtB.disconnect()
  }
}
