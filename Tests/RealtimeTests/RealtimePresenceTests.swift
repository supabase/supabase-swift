//
//  RealtimePresenceTests.swift
//  Realtime
//
//  Created by Guilherme Souza on 08/10/26.
//

import Clocks
import ConcurrencyExtras
import Foundation
import Helpers
import TestHelpers
import Testing

@testable import Realtime

@Suite(.timeLimit(.minutes(1)))
struct RealtimePresenceTests {
  struct User: Codable, Equatable {
    var name: String
  }

  let clock = TestClock()
  let server: FakeRealtimeServer
  let engine: RealtimeEngine
  let wireTopic = "realtime:room"

  init() {
    server = FakeRealtimeServer(clock: clock)
    var configuration = RealtimeEngineConfiguration(url: URL(string: "ws://fake")!)
    configuration.channel = .init(
      rejoin: .steps([.seconds(1)]), rateLimitBackoff: .seconds(30),
      lingerAfterLastListener: .seconds(2))
    configuration.accessToken = { "token" }
    engine = RealtimeEngine(configuration: configuration, transport: server.transport, clock: clock)
  }

  private func makeChannel() -> RealtimeChannel {
    let rest = RealtimeREST(
      baseURL: URL(string: "https://localhost:54321/realtime/v1")!, apikey: "test-key",
      http: HTTPClientConfiguration(), timeout: .seconds(10), clock: clock,
      accessToken: { "test-token" })
    return RealtimeChannel(
      topic: "room", configuration: RealtimeChannelConfiguration(), engine: engine, rest: rest)
  }

  private var joins: [RealtimeMessageV2] { server.sentMessages.filter { $0.event == "phx_join" } }
  private var presencePushes: [RealtimeMessageV2] {
    server.sentMessages.filter { $0.event == "presence" }
  }

  private func presenceEnabled(_ join: RealtimeMessageV2) -> Bool? {
    join.payload["config"]?.objectValue?["presence"]?.objectValue?["enabled"]?.boolValue
  }

  private func settle() async {
    for _ in 0..<1_000 { await Task.yield() }
  }

  private func metas(_ metas: [JSONObject]) -> JSONValue {
    .object(["metas": .array(metas.map(JSONValue.object))])
  }

  // MARK: - Track

  @Test
  func trackBeforeSubscribeThrowsNotSubscribed() async {
    let channel = makeChannel()

    let error = await #expect(throws: RealtimeError.self) {
      try await channel.presence.track(User(name: "ana"))
    }
    #expect(error?.kind == .notSubscribed)
  }

  @Test
  func trackSendsTheTrackPushAndResolvesOnTheReply() async throws {
    let channel = makeChannel()
    _ = channel.presence.states
    try await channel.subscribe()

    try await channel.presence.track(User(name: "ana"))

    #expect(presencePushes.count == 1)
    #expect(presencePushes.first?.payload["event"] == "track")
    #expect(presencePushes.first?.payload["payload"] == ["name": "ana"])
    #expect(await engine.pendingReplyCount == 0)
  }

  @Test
  func untrackSendsTheUntrackPush() async throws {
    let channel = makeChannel()
    try await channel.subscribe()

    try await channel.presence.untrack()

    #expect(presencePushes.map { $0.payload["event"] } == ["untrack"])
  }

  @Test
  func trackInsideTheWindowReturnsOnceQueued() async throws {
    let channel = makeChannel()
    _ = channel.presence.states
    try await channel.subscribe()
    try await channel.presence.track(User(name: "a"))

    try await channel.presence.track(User(name: "b"))

    #expect(presencePushes.count == 1)
    await settle()
    await clock.advance(by: .seconds(6))
    await settle()
    #expect(presencePushes.last?.payload["payload"] == ["name": "b"])
  }

  @Test
  func trackOnAChannelJoinedWithoutPresenceRejoinsWithItThenSendsTheTrack() async throws {
    let channel = makeChannel()
    let events = channel.events
    try await channel.subscribe()

    try await channel.presence.track(User(name: "ana"))

    #expect(joins.map(presenceEnabled) == [false, true])
    let pushed = await waitUntil { [self] in presencePushes.count == 1 }
    #expect(pushed)
    await settle()
    let order = server.sentMessages.map(\.event).filter { $0 == "phx_join" || $0 == "presence" }
    #expect(order == ["phx_join", "phx_join", "presence"])
    #expect(presencePushes.first?.payload["payload"] == ["name": "ana"])
    let resubscribed = try await withTimeout(.seconds(2)) {
      for await event in events { if case .resubscribed = event { return true } }
      return false
    }
    #expect(resubscribed)
  }

  @Test
  func aTrackBeforeSubscribeStillEnablesPresenceOnTheJoin() async throws {
    let channel = makeChannel()
    await #expect(throws: RealtimeError.self) {
      try await channel.presence.track(User(name: "ana"))
    }

    try await channel.subscribe()

    #expect(joins.map(presenceEnabled) == [true])
  }

  @Test
  func aRefusedTrackIsNotResentAfterARejoin() async throws {
    let channel = makeChannel()
    _ = channel.presence.states
    try await channel.subscribe()
    server.dropsClientFrames = true
    let track = Task { try await channel.presence.track(User(name: "ana")) }
    let pushed = await waitUntil { [self] in presencePushes.count == 1 }
    #expect(pushed)
    let push = try #require(presencePushes.first)

    server.push(
      RealtimeMessageV2(
        joinRef: push.joinRef, ref: push.ref, topic: wireTopic, event: "phx_reply",
        payload: ["status": "error", "response": ["reason": "presence refused"]]))

    await #expect(throws: RealtimeError.self) { try await track.value }
    server.dropsClientFrames = false
    server.errorChannel(topic: wireTopic)
    await settle()
    await clock.advance(by: .seconds(1))
    let rejoined = await waitUntil { [engine, wireTopic] in
      await engine.channelState(wireTopic)?.isSubscribed == true
    }
    #expect(rejoined)
    await settle()
    #expect(presencePushes.count == 1)
  }

  @Test
  func rejoinResendsTheTrackedPayload() async throws {
    let channel = makeChannel()
    try await channel.subscribe()
    try await channel.presence.track(User(name: "ana"))

    server.errorChannel(topic: wireTopic)
    await settle()
    await clock.advance(by: .seconds(1))
    let resent = await waitUntil { [self] in presencePushes.count == 2 }

    #expect(resent)
    #expect(presencePushes.last?.payload["payload"] == ["name": "ana"])
    #expect(joins.last.flatMap(presenceEnabled) == true)
  }

  // MARK: - Streams

  @Test
  func stateAndDiffUpdateStatesChangesAndState() async throws {
    let channel = makeChannel()
    var states = channel.presence.states.makeAsyncIterator()
    var changes = channel.presence.changes.makeAsyncIterator()
    try await channel.subscribe()

    server.pushPresenceState(
      topic: wireTopic, state: ["u1": metas([["phx_ref": "r1", "name": "ana"]])])
    server.pushPresenceDiff(
      topic: wireTopic, joins: ["u2": metas([["phx_ref": "r2", "name": "bo"]])],
      leaves: ["u1": metas([["phx_ref": "r1", "name": "ana"]])])

    let first = await states.next()
    let second = await states.next()
    #expect(first?.entries.keys.sorted() == ["u1"])
    #expect(second?.entries.keys.sorted() == ["u2"])
    #expect(second?.entries["u2"]?.first?.payload == ["name": "bo"])

    let sync = await changes.next()
    let diff = await changes.next()
    #expect(sync?.joins["u1"]?.map(\.ref) == ["r1"])
    #expect(diff?.joins["u2"]?.map(\.ref) == ["r2"])
    #expect(diff?.leaves["u1"]?.map(\.ref) == ["r1"])

    #expect(channel.presence.state == second)
  }

  @Test
  func streamBeforeSubscribeEnablesPresenceOnTheJoin() async throws {
    let channel = makeChannel()
    _ = channel.presence.changes

    try await channel.subscribe()

    #expect(joins.map(presenceEnabled) == [true])
  }

  @Test
  func joinWithoutPresenceLeavesItDisabled() async throws {
    let channel = makeChannel()

    try await channel.subscribe()

    #expect(joins.map(presenceEnabled) == [false])
  }

  @Test
  func firstStreamOnASubscribedChannelRejoinsWithPresenceEnabled() async throws {
    let channel = makeChannel()
    try await channel.subscribe()

    _ = channel.presence.states
    let rejoined = await waitUntil { [self] in joins.count == 2 }
    _ = channel.presence.changes
    await settle()

    #expect(rejoined)
    #expect(joins.map(presenceEnabled) == [false, true])
  }

  @Test
  func removingTheChannelClearsTheState() async throws {
    let channel = makeChannel()
    var states = channel.presence.states.makeAsyncIterator()
    try await channel.subscribe()
    server.pushPresenceState(topic: wireTopic, state: ["u1": metas([["phx_ref": "r1"]])])
    _ = await states.next()

    await engine.removeChannel(wireTopic, owner: channel.owner)

    #expect(channel.presence.state.entries.isEmpty)
  }

  // MARK: - Decode

  private let mixedState = PresenceState(entries: [
    "u1": [
      PresenceEntry(ref: "r1", payload: ["name": "ana"]),
      PresenceEntry(ref: "r2", payload: ["age": 3]),
    ],
    "u2": [PresenceEntry(ref: "r3", payload: ["age": 4])],
  ])

  @Test
  func decodeSkipsUndecodableEntriesAndEmptyKeys() throws {
    let decoded = try mixedState.decode(as: User.self)

    #expect(decoded == ["u1": [User(name: "ana")]])
  }

  @Test
  func decodeThrowsOnTheFirstFailureWhenNotIgnoring() {
    let error = #expect(throws: RealtimeError.self) {
      try mixedState.decode(as: User.self, ignoringUndecodable: false)
    }
    #expect(error?.kind == .decoding)
  }

  @Test
  func entryDecodesItsPayload() throws {
    let entry = PresenceEntry(ref: "r1", payload: ["name": "ana"])

    #expect(try entry.decode() == User(name: "ana"))
    #expect(throws: RealtimeError.self) { try entry.decode(as: Int.self) }
  }
}
