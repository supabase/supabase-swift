//
//  UpdateTokenTests.swift
//  RealtimeV3Tests
//
//  Created by Guilherme Souza on 29/06/26.
//

import ConcurrencyExtras
import Foundation
import Helpers
import Testing

@testable import RealtimeV3

@Suite struct UpdateTokenTests {

  // MARK: - updateTokenPushesAccessTokenToJoinedChannel

  /// Verifies that updateToken pushes an access_token event to each joined channel.
  @Test func updateTokenPushesAccessTokenToJoinedChannel() async throws {
    let (transport, server) = InMemoryTransport.pair()
    let rt = Realtime(url: URL(string: "wss://x")!, apiKey: "k", transport: transport)
    let channel = await rt.channel("room:1")

    // Auto-reply to phx_join so channel reaches .joined.
    server.autoReplyToJoins()
    try await channel.subscribe()

    // Confirm joined.
    let joinedState = await channel.state.first(where: { _ in true })
    #expect(joinedState == .joined)

    // Subscribe to client frames BEFORE calling updateToken to ensure we observe the frame.
    let clientFrames = server.subscribeToClientFrames()

    // Call updateToken — must return immediately (no ACK expected per Finding I1).
    try await rt.updateToken("new-token")

    // Read the next frame from the client observer with a bounded loop.
    var foundAccessTokenFrame = false
    var iterations = 0
    for await frame in clientFrames {
      iterations += 1
      guard case .text(let text) = frame else {
        if iterations > 20 { break }
        continue
      }
      // Decode the Phoenix array: [joinRef, ref, topic, event, payload]
      guard let data = text.data(using: .utf8),
        let array = try? JSONDecoder().decode([AnyJSON].self, from: data),
        array.count >= 5
      else {
        if iterations > 20 { break }
        continue
      }
      guard let event = array[3].stringValue, event == "access_token" else {
        if iterations > 20 { break }
        continue
      }
      guard let topic = array[2].stringValue, topic == "realtime:room:1" else {
        if iterations > 20 { break }
        continue
      }
      // Check payload: {"access_token": "new-token"}
      if let payload = array[4].objectValue,
        let tokenValue = payload["access_token"]?.stringValue,
        tokenValue == "new-token"
      {
        foundAccessTokenFrame = true
        break
      }
      if iterations > 20 { break }
    }
    #expect(foundAccessTokenFrame)
  }

  // MARK: - updateTokenSkipsUnjoinedChannels

  /// Verifies that updateToken does NOT push an access_token event to unjoined channels.
  /// Uses a Task-with-timeout pattern so the test never hangs: if no access_token frame
  /// arrives within a bounded window, the assertion passes (the channel was correctly skipped).
  @Test func updateTokenSkipsUnjoinedChannels() async throws {
    let (transport, server) = InMemoryTransport.pair()
    let rt = Realtime(url: URL(string: "wss://x")!, apiKey: "k", transport: transport)

    // Create a channel but do NOT subscribe — it stays .unsubscribed.
    _ = await rt.channel("room:unjoined")

    // Subscribe to client frames BEFORE calling updateToken.
    let clientFrames = server.subscribeToClientFrames()

    // Track whether an access_token frame was (incorrectly) sent.
    let accessTokenSeen = LockIsolated(false)

    // Spawn a bounded observer: reads up to 5 frames then finishes.
    // Because no joined channel exists, no frames are expected at all.
    // We cancel this task after updateToken returns to avoid hanging.
    let observerTask = Task {
      var count = 0
      for await frame in clientFrames {
        count += 1
        if case .text(let text) = frame, text.contains("\"access_token\"") {
          accessTokenSeen.withValue { $0 = true }
          break
        }
        if count >= 5 { break }
      }
    }

    try await rt.updateToken("new-token")

    // Give the observer a brief moment to catch any spurious frame, then cancel it.
    try? await Task.sleep(nanoseconds: 10_000_000)  // 10 ms
    observerTask.cancel()

    #expect(accessTokenSeen.value == false)
  }

  // MARK: - updateTokenStoresTokenForFutureJoins

  /// Verifies that after updateToken, a subsequent subscribe() carries the new token
  /// in its join payload.
  @Test func updateTokenStoresTokenForFutureJoins() async throws {
    let (transport, server) = InMemoryTransport.pair()
    let rt = Realtime(url: URL(string: "wss://x")!, apiKey: "k", transport: transport)

    // Store the new token before any channel is joined.
    try await rt.updateToken("stored-token")

    // Now create a channel and subscribe; the join payload should carry "stored-token".
    let channel = await rt.channel("room:2")

    // Subscribe to client frames BEFORE subscribing the channel.
    let clientFrames = server.subscribeToClientFrames()
    let capturedJoinFrame = LockIsolated<String?>(nil)

    // Capture the join frame in a background task.
    let captureTask = Task.detached {
      for await frame in clientFrames {
        guard case .text(let text) = frame, text.contains("phx_join") else { continue }
        capturedJoinFrame.withValue { $0 = text }
        break
      }
    }

    server.autoReplyToJoins()
    try await channel.subscribe()
    // subscribe() returns only after the join is confirmed, so the join frame was sent.
    // Give the capture task a brief moment to process the frame from the stream.
    try? await Task.sleep(nanoseconds: 50_000_000)  // 50 ms
    captureTask.cancel()

    let joinFrame = capturedJoinFrame.value
    #expect(joinFrame != nil)
    #expect(joinFrame?.contains("stored-token") == true)
  }
}
