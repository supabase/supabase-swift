//
//  PresenceTrackTests.swift
//  RealtimeV3Tests
//
//  Created by Guilherme Souza on 29/06/26.
//

import ConcurrencyExtras
import Foundation
import Helpers
import Testing

@testable import RealtimeV3

// MARK: - Test Payload

private struct UserPresence: Codable, Sendable {
  let userId: String
  let status: String
}

// MARK: - PresenceTrackTests

@Suite struct PresenceTrackTests {

  // MARK: - trackOnJoinedChannelEmitsPresenceFrame

  /// track() on a joined channel sends a presence/track frame; cancel() sends an untrack frame.
  @Test func trackOnJoinedChannelEmitsPresenceFrame() async throws {
    let (transport, server) = InMemoryTransport.pair()
    let rt = Realtime(url: URL(string: "wss://x")!, apiKey: "k", transport: transport)
    let channel = await rt.channel("room:1")

    // Enable auto-replies BEFORE calls so acks arrive without clock tricks.
    server.autoReplyToJoins()
    server.autoReplyToPresence()

    try await channel.subscribe()

    // Observe frames in background BEFORE calling track.
    let capturedFrames = LockIsolated<[TransportFrame]>([])
    let clientFrames = server.subscribeToClientFrames()
    let observeTask = Task {
      for await frame in clientFrames {
        capturedFrames.withValue { $0.append(frame) }
      }
    }
    defer { observeTask.cancel() }

    let handle = try await channel.presence.track(
      UserPresence(userId: "u1", status: "active")
    )

    // Verify a text frame with channel event "presence" and inner event "track" was sent.
    let frames = capturedFrames.value
    let trackFrame = frames.first { frame in
      guard case .text(let text) = frame else { return false }
      return text.contains("\"presence\"") && text.contains("\"track\"")
    }
    #expect(trackFrame != nil, "Expected a presence/track frame to be sent")

    // cancel() should send an untrack frame.
    try await handle.cancel()

    // Give the frame a moment to appear in the captured array.
    var waitCount = 0
    while waitCount < 100 {
      let hasUntrack = capturedFrames.value.contains { frame in
        guard case .text(let text) = frame else { return false }
        return text.contains("\"presence\"") && text.contains("\"untrack\"")
      }
      if hasUntrack { break }
      try await Task.sleep(nanoseconds: 1_000_000)  // 1ms
      waitCount += 1
    }

    let hasUntrackFrame = capturedFrames.value.contains { frame in
      guard case .text(let text) = frame else { return false }
      return text.contains("\"presence\"") && text.contains("\"untrack\"")
    }
    #expect(hasUntrackFrame, "Expected a presence/untrack frame to be sent after cancel()")
  }

  // MARK: - trackBeforeSubscribeThrowsNotSubscribed

  /// track() on a channel that hasn't been subscribed throws .notSubscribed.
  @Test func trackBeforeSubscribeThrowsNotSubscribed() async throws {
    let (transport, _) = InMemoryTransport.pair()
    let rt = Realtime(url: URL(string: "wss://x")!, apiKey: "k", transport: transport)
    let channel = await rt.channel("room:1")

    do {
      _ = try await channel.presence.track(UserPresence(userId: "u1", status: "active"))
      Issue.record("Expected .notSubscribed to be thrown")
    } catch {
      if case .notSubscribed = error {
        // Expected — success.
      } else {
        Issue.record("Expected .notSubscribed, got \(error)")
      }
    }
  }

  // MARK: - cancelIsIdempotent

  /// Calling cancel() twice must not hang or crash.
  @Test func cancelIsIdempotent() async throws {
    let (transport, server) = InMemoryTransport.pair()
    let rt = Realtime(url: URL(string: "wss://x")!, apiKey: "k", transport: transport)
    let channel = await rt.channel("room:1")

    server.autoReplyToJoins()
    server.autoReplyToPresence()

    try await channel.subscribe()

    let handle = try await channel.presence.track(UserPresence(userId: "u1", status: "active"))

    // First cancel — must succeed.
    try await handle.cancel()

    // Second cancel — must be a no-op (idempotent), not hang, not throw.
    try await handle.cancel()
  }

  // MARK: - updateSendsNewTrackFrame

  /// update() re-sends a presence/track frame with the new state.
  @Test func updateSendsNewTrackFrame() async throws {
    let (transport, server) = InMemoryTransport.pair()
    let rt = Realtime(url: URL(string: "wss://x")!, apiKey: "k", transport: transport)
    let channel = await rt.channel("room:1")

    server.autoReplyToJoins()
    server.autoReplyToPresence()

    try await channel.subscribe()

    let handle = try await channel.presence.track(UserPresence(userId: "u1", status: "active"))

    // Observe frames.
    let capturedFrames = LockIsolated<[TransportFrame]>([])
    let clientFrames = server.subscribeToClientFrames()
    let observeTask = Task {
      for await frame in clientFrames {
        capturedFrames.withValue { $0.append(frame) }
      }
    }
    defer { observeTask.cancel() }

    // Update with a new state.
    try await handle.update(UserPresence(userId: "u1", status: "away"))

    // Give the frame a moment to appear.
    var waitCount = 0
    while waitCount < 100 {
      let hasTrack = capturedFrames.value.contains { frame in
        guard case .text(let text) = frame else { return false }
        return text.contains("\"presence\"") && text.contains("\"track\"") && text.contains("away")
      }
      if hasTrack { break }
      try await Task.sleep(nanoseconds: 1_000_000)  // 1ms
      waitCount += 1
    }

    let hasUpdateFrame = capturedFrames.value.contains { frame in
      guard case .text(let text) = frame else { return false }
      return text.contains("\"presence\"") && text.contains("\"track\"") && text.contains("away")
    }
    #expect(hasUpdateFrame, "Expected a presence/track frame with updated state to be sent")

    try await handle.cancel()
  }
}
