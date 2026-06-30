//
//  ConnectionE2ETests.swift
//  RealtimeV3IntegrationTests
//
//  Created by Guilherme Souza on 29/06/26.
//

import Foundation
import RealtimeV3
import Testing

/// IE-1: Connection lifecycle e2e tests against a live local Supabase instance.
///
/// These tests require a running local Supabase stack:
///   cd Tests/RealtimeV3IntegrationTests/supabase && supabase start
///
/// They are automatically skipped when the instance is not reachable.
@Suite("IE-1 Connection Lifecycle", .requiresLocalSupabase)
struct ConnectionE2ETests {

  // MARK: - IE-1a: connect -> connected -> disconnect -> closed

  @Test("connects to live instance and transitions through connection states")
  func connectsToLiveInstance() async throws {
    let rt = IntegrationEnv.makeRealtime()
    let statusStream = await rt.status

    // connect() should not throw
    try await rt.connect()

    // Observe that status reaches .connected
    try await waitFor(
      statusStream,
      timeout: .seconds(10),
      description: "status == .connected"
    ) { status in
      if case .connected = status.state { return true }
      return false
    }

    // Disconnect
    await rt.disconnect()

    // After disconnect the status should reach .closed or .idle
    let postDisconnectStream = await rt.status
    try await waitFor(
      postDisconnectStream,
      timeout: .seconds(5),
      description: "status == .closed or .idle after disconnect"
    ) { status in
      switch status.state {
      case .closed, .idle: return true
      default: return false
      }
    }
  }

  // MARK: - IE-1b: repeated connect is idempotent

  @Test("repeated connect() calls are idempotent once connected")
  func repeatedConnectIsIdempotent() async throws {
    let rt = IntegrationEnv.makeRealtime()

    try await rt.connect()

    // Second connect should be a no-op and not throw
    try await rt.connect()

    // Verify still connected
    let statusStream = await rt.status
    try await waitFor(
      statusStream,
      timeout: .seconds(5),
      description: "status == .connected after second connect()"
    ) { status in
      if case .connected = status.state { return true }
      return false
    }

    await rt.disconnect()
  }
}
