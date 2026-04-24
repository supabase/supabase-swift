//
//  PresenceTests.swift
//  _RealtimeTests
//
//  Created by Guilherme Souza on 24/04/25.
//

import ConcurrencyExtras
import Foundation
import Testing
@testable import _Realtime

// Types used in PresenceTests — must be at file scope for Swift Testing macro compatibility.
private struct TrackState: Codable, Sendable { let userId: String }
private struct PresenceUserState: Decodable, Sendable { let name: String }

@Suite struct PresenceTests {
  static let testURL = URL(string: "ws://localhost:4000/realtime/v1")!

  /// Builds a connected Realtime + channel pair. The returned auto-reply task responds to
  /// phx_join and presence pushes. All frames received are also appended to `receivedTexts`
  /// so tests can inspect them without competing with the auto-reply task.
  func makeConnectedChannel(topic: String = "room:1") async throws -> (
    realtime: Realtime,
    channel: Channel,
    server: InMemoryServer,
    receivedTexts: LockIsolated<[String]>,
    autoReplyTask: Task<Void, Never>
  ) {
    let (transport, server) = InMemoryTransport.pair()
    let realtime = Realtime(url: Self.testURL, apiKey: .literal("key"), transport: transport)
    try await realtime.connect()

    let receivedTexts = LockIsolated<[String]>([])

    let autoReplyTask = Task { [server, receivedTexts] in
      do {
        for try await frame in server.receivedFrames {
          guard case .text(let text) = frame,
                let msg = try? PhoenixSerializer.decodeText(text) else { continue }
          receivedTexts.withValue { $0.append(text) }
          if msg.event == "phx_join" || msg.event == "presence" {
            let reply = PhoenixMessage(
              joinRef: msg.joinRef, ref: msg.ref, topic: msg.topic,
              event: "phx_reply",
              payload: ["status": "ok", "response": .object([:])]
            )
            await server.send(.text(try! PhoenixSerializer.encodeText(reply)))
          }
        }
      } catch {
        // stream ended
      }
    }

    let channel = await realtime.channel(topic)
    return (realtime, channel, server, receivedTexts, autoReplyTask)
  }

  @Test func trackSendsPresenceEvent() async throws {
    let (realtime, channel, _, receivedTexts, autoReplyTask) = try await makeConnectedChannel()
    defer { autoReplyTask.cancel() }
    _ = realtime  // retain

    try await channel.join()
    try await Task.sleep(for: .milliseconds(50))

    let handle = try await channel.presence.track(TrackState(userId: "u1"))
    try await Task.sleep(for: .milliseconds(50))

    // Auto-reply task captures all received texts — check for presence push
    let texts = receivedTexts.value
    #expect(texts.contains { $0.contains("presence") })

    try await handle.cancel()
  }

  @Test func observeDeliversPresenceSnapshot() async throws {
    let (realtime, channel, server, _, autoReplyTask) = try await makeConnectedChannel()
    defer { autoReplyTask.cancel() }
    _ = realtime  // retain

    try await channel.join()
    try await Task.sleep(for: .milliseconds(50))

    let states = await channel.presence.observe(PresenceUserState.self)
    let snapshots = LockIsolated<[PresenceState<PresenceUserState>]>([])
    let task = Task {
      for await s in states { snapshots.withValue { $0.append(s) } }
    }
    defer { task.cancel() }

    // Server pushes presence_state
    let presenceMsg = PhoenixMessage(
      joinRef: nil, ref: nil, topic: "room:1", event: "presence_state",
      payload: ["alice": .object(["metas": .array([.object(["name": "Alice"])])])]
    )
    await server.send(.text(try! PhoenixSerializer.encodeText(presenceMsg)))

    try await Task.sleep(for: .milliseconds(50))
    #expect(!snapshots.value.isEmpty)
    #expect(snapshots.value.first?.active["alice"]?.first?.name == "Alice")
  }

  @Test func diffsDeliversPresenceDiff() async throws {
    let (realtime, channel, server, _, autoReplyTask) = try await makeConnectedChannel()
    defer { autoReplyTask.cancel() }
    _ = realtime  // retain

    try await channel.join()
    try await Task.sleep(for: .milliseconds(50))

    let diffStream = await channel.presence.diffs(PresenceUserState.self)
    let diffs = LockIsolated<[PresenceDiff<PresenceUserState>]>([])
    let task = Task {
      for await d in diffStream { diffs.withValue { $0.append(d) } }
    }
    defer { task.cancel() }

    // Server pushes presence_diff
    let diffMsg = PhoenixMessage(
      joinRef: nil, ref: nil, topic: "room:1", event: "presence_diff",
      payload: [
        "joins": .object(["bob": .object(["metas": .array([.object(["name": "Bob"])])])]),
        "leaves": .object([:]),
      ]
    )
    await server.send(.text(try! PhoenixSerializer.encodeText(diffMsg)))

    try await Task.sleep(for: .milliseconds(50))
    #expect(!diffs.value.isEmpty)
    #expect(diffs.value.first?.joined.first?.1.name == "Bob")
  }
}
