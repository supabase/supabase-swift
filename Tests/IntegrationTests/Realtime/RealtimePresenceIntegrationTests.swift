//
//  RealtimePresenceIntegrationTests.swift
//  IntegrationTests
//
//  Created by Guilherme Souza on 08/10/26.
//

import Foundation
import Helpers
import Realtime
import Testing

@Suite(
  .serialized,
  .enabled(if: ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil),
  .disabled(if: WebSocketAvailability.isMissing, "libcurl has no WebSocket support")
)
struct RealtimePresenceIntegrationTests {
  struct User: Codable, Equatable, Sendable {
    var name: String
  }

  struct StreamEnded: Error {}

  private func uniqueTopic() -> String { "it-\(UUID())" }

  /// Runs `body` with two sockets and closes both afterwards, also when `body` throws.
  private func withEngines(
    _ body: (RealtimeEngine, RealtimeEngine) async throws -> Void
  ) async throws {
    let a = LiveRealtime.engine()
    let b = LiveRealtime.engine()
    do {
      try await body(a, b)
    } catch {
      await a.disconnect()
      await b.disconnect()
      throw error
    }
    await a.disconnect()
    await b.disconnect()
  }

  /// The first element that passes `predicate`, within 10 seconds.
  private func first<Element>(
    _ stream: RealtimeStream<Element>,
    where predicate: @escaping @Sendable (Element) -> Bool = { _ in true }
  ) async throws -> Element {
    try await withTimeout(.seconds(10)) {
      for await element in stream where predicate(element) { return element }
      throw StreamEnded()
    }
  }

  private func names(_ state: PresenceState) -> [String] {
    ((try? state.decode(as: User.self)) ?? [:]).values.flatMap { $0.map(\.name) }.sorted()
  }

  // MARK: - Tests

  @Test
  func trackUpdateAndUntrackReachTheOtherClient() async throws {
    try await withEngines { a, b in
      let topic = uniqueTopic()
      let channelA = LiveRealtime.channel(topic, engine: a)
      let channelB = LiveRealtime.channel(topic, engine: b)
      let states = channelB.presence.states
      let changes = channelB.presence.changes
      try await channelB.subscribe()
      try await channelA.subscribe()

      try await channelA.presence.track(User(name: "ana"))

      let joined = try await first(states) { names($0) == ["ana"] }
      #expect(channelB.presence.state == joined)
      let join = try await first(changes) { !$0.joins.isEmpty }
      #expect(join.joins.values.flatMap { $0 }.first?.payload == ["name": "ana"])

      // Each step listens on new streams: a stream value is iterated once.
      let updates = channelB.presence.states
      try await channelA.presence.track(User(name: "ana 2"))
      _ = try await first(updates) { names($0) == ["ana 2"] }

      let leaves = channelB.presence.changes
      try await channelA.presence.untrack()
      let leave = try await first(leaves) { $0.joins.isEmpty && !$0.leaves.isEmpty }
      #expect(leave.leaves.values.flatMap { $0 }.first?.payload == ["name": "ana 2"])
      #expect(channelB.presence.state.entries.isEmpty)
    }
  }

  @Test
  func presenceKeyGroupsEntries() async throws {
    try await withEngines { a, b in
      let topic = uniqueTopic()
      let channelA = LiveRealtime.channel(topic, engine: a) { $0.presence.key = "user-a" }
      let channelB = LiveRealtime.channel(topic, engine: b) { $0.presence.key = "user-b" }
      let states = channelB.presence.states
      try await channelB.subscribe()
      try await channelA.subscribe()

      try await channelA.presence.track(User(name: "ana"))
      try await channelB.presence.track(User(name: "bo"))

      let state = try await first(states) { $0.entries.count == 2 }
      #expect(Set(state.entries.keys) == ["user-a", "user-b"])
      #expect(try state.decode(as: User.self)["user-a"] == [User(name: "ana")])
    }
  }

  @Test
  func firstStreamOnAJoinedChannelReceivesTheSet() async throws {
    try await withEngines { a, b in
      let topic = uniqueTopic()
      let channelA = LiveRealtime.channel(topic, engine: a)
      let channelB = LiveRealtime.channel(topic, engine: b)
      try await channelA.subscribe()
      try await channelA.presence.track(User(name: "ana"))
      try await channelB.subscribe()

      let states = channelB.presence.states

      _ = try await first(states) { names($0) == ["ana"] }
    }
  }

  /// realApplicationScenario_BroadcastAndPresence
  @Test
  func socketDropRetracksAfterTheRejoin() async throws {
    try await withEngines { a, b in
      let topic = uniqueTopic()
      let channelA = LiveRealtime.channel(topic, engine: a)
      let channelB = LiveRealtime.channel(topic, engine: b)
      let changes = channelB.presence.changes
      try await channelB.subscribe()
      try await channelA.subscribe()
      try await channelA.presence.track(User(name: "ana"))
      _ = try await first(changes) { !$0.joins.isEmpty }

      let leaves = channelB.presence.changes
      await a.pause()
      _ = try await first(leaves) { !$0.leaves.isEmpty }
      let joins = channelB.presence.changes
      await a.resume()

      let rejoined = try await first(joins) { !$0.joins.isEmpty }
      #expect(rejoined.joins.values.flatMap { $0 }.first?.payload == ["name": "ana"])
    }
  }
}
