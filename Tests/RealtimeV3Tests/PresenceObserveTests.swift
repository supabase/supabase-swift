//
//  PresenceObserveTests.swift
//  RealtimeV3Tests
//
//  Created by Guilherme Souza on 29/06/26.
//

import ConcurrencyExtras
import Foundation
import Testing

@testable import RealtimeV3

// MARK: - Test Payload

private struct UserPresence: Codable, Sendable, Equatable {
  let userId: String
  let status: String
}

// MARK: - PresenceObserveTests

@Suite struct PresenceObserveTests {

  // MARK: - observeYieldsSnapshotThenDiff

  /// observe() yields an initial snapshot from presence_state, then an updated snapshot
  /// after a presence_diff that accumulates the new state.
  @Test func observeYieldsSnapshotThenDiff() async throws {
    let (transport, server) = InMemoryTransport.pair()
    let rt = Realtime(url: URL(string: "wss://x")!, apiKey: "k", transport: transport)
    let channel = await rt.channel("room:1")

    server.autoReplyToJoins()
    try await channel.subscribe()

    // Register the observe stream BEFORE injecting any frames.
    let stream = await channel.presence.observe(UserPresence.self)
    var iter = stream.makeAsyncIterator()

    // Inject a presence_state frame.
    server.send(
      .text(
        #"["1",null,"realtime:room:1","presence_state",{"u1":{"metas":[{"phx_ref":"r1","userId":"u1","status":"active"}]}}]"#
      ))

    // Read first value: initial snapshot.
    let snapshot = await iter.next()
    #expect(snapshot != nil)
    #expect(snapshot?.lastDiff == nil, "Initial snapshot should have nil lastDiff")
    let u1Values = snapshot?.active["u1"]
    #expect(u1Values?.count == 1)
    #expect(u1Values?.first == UserPresence(userId: "u1", status: "active"))

    // Inject a presence_diff frame adding u2.
    server.send(
      .text(
        #"["2",null,"realtime:room:1","presence_diff",{"joins":{"u2":{"metas":[{"phx_ref":"r2","userId":"u2","status":"idle"}]}},"leaves":{}}]"#
      ))

    // Read second value: accumulated snapshot with diff.
    let updated = await iter.next()
    #expect(updated != nil)
    #expect(updated?.lastDiff != nil, "Updated snapshot should have non-nil lastDiff")

    // Both u1 and u2 should be present in the accumulated active map.
    let updatedU1 = updated?.active["u1"]
    #expect(updatedU1?.count == 1)
    #expect(updatedU1?.first == UserPresence(userId: "u1", status: "active"))

    let updatedU2 = updated?.active["u2"]
    #expect(updatedU2?.count == 1)
    #expect(updatedU2?.first == UserPresence(userId: "u2", status: "idle"))
  }

  // MARK: - diffsYieldsOnlyDiffs

  /// diffs() stream does NOT emit on presence_state, emits a PresenceDiff on presence_diff.
  @Test func diffsYieldsOnlyDiffs() async throws {
    let (transport, server) = InMemoryTransport.pair()
    let rt = Realtime(url: URL(string: "wss://x")!, apiKey: "k", transport: transport)
    let channel = await rt.channel("room:1")

    server.autoReplyToJoins()
    try await channel.subscribe()

    // Register the diffs stream BEFORE injecting any frames.
    let stream = await channel.presence.diffs(UserPresence.self)
    var iter = stream.makeAsyncIterator()

    // Inject presence_state — should NOT emit on diffs stream.
    server.send(
      .text(
        #"["1",null,"realtime:room:1","presence_state",{"u1":{"metas":[{"phx_ref":"r1","userId":"u1","status":"active"}]}}]"#
      ))

    // Inject presence_diff adding u2 — SHOULD emit on diffs stream.
    server.send(
      .text(
        #"["2",null,"realtime:room:1","presence_diff",{"joins":{"u2":{"metas":[{"phx_ref":"r2","userId":"u2","status":"idle"}]}},"leaves":{}}]"#
      ))

    // The FIRST value from diffs() must be the presence_diff (not presence_state).
    let diff = await iter.next()
    #expect(diff != nil)

    // Check that u2 was joined.
    let joinedKeys = diff?.joined.map { $0.0 } ?? []
    #expect(joinedKeys.contains("u2"))
    let joinedValues = diff?.joined.map { $0.1 } ?? []
    #expect(joinedValues.contains(UserPresence(userId: "u2", status: "idle")))

    // No leaves.
    #expect(diff?.left.isEmpty == true)
  }

  // MARK: - leaveFinishesPresenceStreams

  /// An open observe stream finishes when channel.leave() is called.
  @Test func leaveFinishesPresenceStreams() async throws {
    let (transport, server) = InMemoryTransport.pair()
    let rt = Realtime(url: URL(string: "wss://x")!, apiKey: "k", transport: transport)
    let channel = await rt.channel("room:1")

    server.autoReplyToJoins()
    server.autoReplyToLeaves()
    try await channel.subscribe()

    // Register stream BEFORE calling leave().
    let stream = await channel.presence.observe(UserPresence.self)

    let done = LockIsolated(false)
    let collectionTask = Task {
      for await _ in stream {
        // No messages expected before leave.
      }
      // Stream ended cleanly (no throw — observe is non-throwing).
      done.withValue { $0 = true }
    }

    // Leave the channel — this should finish the observe stream.
    try await channel.leave()

    // Wait for collection task to finish (bounded to 1s).
    var waitIterations = 0
    while !done.value {
      try await Task.sleep(nanoseconds: 1_000_000)  // 1ms
      waitIterations += 1
      if waitIterations > 1000 {
        Issue.record("Presence observe stream was not finished after leave() within 1s")
        collectionTask.cancel()
        return
      }
    }
    collectionTask.cancel()

    #expect(done.value, "Observe stream should have finished after leave()")
  }
}
