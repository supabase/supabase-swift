//
//  RealtimeV3IntegrationTests.swift
//  _RealtimeTests
//
//  Created by Guilherme Souza on 24/04/25.
//

import Foundation
import Testing

@testable import _Realtime

// Integration tests require a running local Supabase instance.
// Start with: cd Tests/IntegrationTests && supabase start
// These are disabled by default so the suite runs cleanly without a local stack.

@Suite(.disabled("Requires local Supabase — enable by removing .disabled"))
struct RealtimeV3IntegrationTests {
  static let url = URL(
    string: ProcessInfo.processInfo.environment["SUPABASE_REALTIME_URL"]
      ?? "ws://localhost:54321/realtime/v1"
  )!
  static let anonKey =
    ProcessInfo.processInfo.environment["SUPABASE_ANON_KEY"]
    ?? "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRFA0NiK7kyqd6sDnYoIkejqjsoBJarVLL6PB-dADMI"

  func makeRealtime() -> Realtime {
    Realtime(url: Self.url, apiKey: .literal(Self.anonKey))
  }

  @Test func connectAndDisconnect() async throws {
    let realtime = makeRealtime()
    try await realtime.connect()
    #expect(await realtime.currentStatus == .connected)
    await realtime.disconnect()
  }

  @Test func broadcastRoundTrip() async throws {
    struct Msg: Codable, Sendable, Equatable { let text: String }
    let r1 = makeRealtime()
    let r2 = makeRealtime()
    try await r1.connect()
    try await r2.connect()

    let sender = await r1.channel("integration:broadcast")
    let receiver = await r2.channel("integration:broadcast") {
      $0.broadcast.receiveOwnBroadcasts = false
    }

    nonisolated(unsafe) var received: [Msg] = []
    let listenTask = Task {
      for try await msg in await receiver.broadcasts(of: Msg.self, event: "test") {
        received.append(msg)
      }
    }
    try await Task.sleep(for: .milliseconds(500))

    try await sender.join()
    try await sender.broadcast(Msg(text: "hello integration"), as: "test")
    try await Task.sleep(for: .seconds(1))

    #expect(received.contains(Msg(text: "hello integration")))

    listenTask.cancel()
    try await sender.leave()
    try await receiver.leave()
  }
}
