//
//  RealtimeChannelPresenceTests.swift
//  RealtimeTests
//
//  Created by Guilherme Souza on 20/10/26.
//

import Clocks
import Foundation
import Testing

@testable import Realtime

@Suite
struct RealtimeChannelPresenceTests {
  // MARK: - Sync state

  @Test
  func stateThenDiffBuildsThePresenceSet() async throws {
    let host = await RealtimeTestHost()
    let channel = await host.client.channel("room")
    var changes = await channel.presenceChanges().makeAsyncIterator()
    try await subscribe(channel, on: host)

    sendPresenceState(["u1": metas([("r1", "ana")])], on: channel, host: host)
    _ = await changes.next()
    sendPresenceDiff(joins: ["u2": metas([("r2", "bo")])], on: channel, host: host)
    _ = await changes.next()

    let state = await channel.presence.state
    #expect(Set(state.entries.keys) == ["u1", "u2"])
    #expect(state.entries["u1"]?.first?.payload == ["name": "ana"])

    sendPresenceDiff(leaves: ["u1": metas([("r1", "ana")])], on: channel, host: host)
    let leave = try #require(await changes.next())
    #expect(leave.leaves.keys.contains("u1"))
    #expect(Set(await channel.presence.state.entries.keys) == ["u2"])
  }

  @Test
  func diffBeforeTheFirstStateIsHeldAndDeliveredAfterIt() async throws {
    let host = await RealtimeTestHost()
    let channel = await host.client.channel("room")
    var changes = await channel.presenceChanges().makeAsyncIterator()
    try await subscribe(channel, on: host)

    sendPresenceDiff(joins: ["u2": metas([("r2", "bo")])], on: channel, host: host)
    sendPresenceState(["u1": metas([("r1", "ana")])], on: channel, host: host)

    let first = try #require(await changes.next())
    #expect(first.rawMessage.event == ChannelEvent.presenceState)
    #expect(Set(first.joins.keys) == ["u1"])
    let second = try #require(await changes.next())
    #expect(second.rawMessage.event == ChannelEvent.presenceDiff)
    #expect(Set(second.joins.keys) == ["u2"])
    #expect(Set(await channel.presence.state.entries.keys) == ["u1", "u2"])
  }

  // MARK: - Re-track after rejoin

  @Test
  func trackIsResentWithTheSamePayloadAfterARejoin() async throws {
    let host = await RealtimeTestHost()
    let channel = await host.client.channel("room")
    let firstJoin = try await subscribe(channel, on: host)
    #expect(firstJoin.payload.presenceEnabled == false)

    try await channel.track(state: ["name": "ana"])
    let firstTrack = try await host.receive(where: Self.isTrack)

    try await dropSocketAndRejoin(channel, after: firstJoin, on: host)

    await host.waitUntil { host.frames.filter(Self.isTrack).count == 2 }
    let tracks = host.frames.filter(Self.isTrack)
    #expect(tracks.last?.payload == firstTrack.payload)
    #expect(tracks.last?.joinRef != firstTrack.joinRef)
  }

  @Test
  func rejoinTurnsPresenceOnWhenAPayloadIsTracked() async throws {
    let host = await RealtimeTestHost()
    let channel = await host.client.channel("room")
    let firstJoin = try await subscribe(channel, on: host)
    try await channel.track(state: ["name": "ana"])

    let rejoin = try await dropSocketAndRejoin(channel, after: firstJoin, on: host)

    #expect(rejoin.payload.presenceEnabled == true)
  }

  @Test
  func untrackForgetsThePayload() async throws {
    let host = await RealtimeTestHost()
    let channel = await host.client.channel("room")
    try await subscribe(channel, on: host)

    try await channel.track(state: ["name": "ana"])
    #expect(await channel.presence.trackedPayload == ["name": "ana"])
    try await channel.untrack()

    #expect(await channel.presence.trackedPayload == nil)
    #expect(await channel.isPresenceInUse == false)
  }

  @Test
  func unsubscribeForgetsThePayload() async throws {
    let host = await RealtimeTestHost()
    let channel = await host.client.channel("room")
    try await subscribe(channel, on: host)
    try await channel.track(state: ["name": "ana"])

    async let unsubscribed: Void = channel.unsubscribe()
    let leave = try await host.receive(event: ChannelEvent.leave)
    host.server?.send(
      RealtimeMessageV2(
        joinRef: leave.joinRef, ref: nil, topic: channel.topic, event: ChannelEvent.close,
        payload: [:]
      )
    )
    await unsubscribed

    #expect(await channel.presence.trackedPayload == nil)
  }

  @Test
  func untrackDuringARejoinForgetsThePayload() async throws {
    let host = await RealtimeTestHost()
    let channel = await host.client.channel("room")
    let firstJoin = try await subscribe(channel, on: host)
    try await channel.track(state: ["n": 1])
    _ = try await host.receive(where: Self.isTrack)

    try await dropSocketAndRejoin(channel, after: firstJoin, on: host) {
      try await channel.untrack()
    }
    try await channel.track(state: ["n": 2])

    await host.waitUntil { host.frames.filter(Self.isTrack).count == 2 }
    #expect(host.frames.filter(Self.isTrack).map(Self.trackedState) == [["n": 1], ["n": 2]])
  }

  @Test
  func trackDuringARejoinIsSentOnceTheJoinIsConfirmed() async throws {
    let host = await RealtimeTestHost()
    let channel = await host.client.channel("room")
    let firstJoin = try await subscribe(channel, on: host)
    try await channel.track(state: ["n": 1])

    try await dropSocketAndRejoin(channel, after: firstJoin, on: host) {
      try await channel.track(state: ["n": 2])
    }

    await host.waitUntil { host.frames.filter(Self.isTrack).count == 2 }
    #expect(host.frames.filter(Self.isTrack).map(Self.trackedState) == [["n": 1], ["n": 2]])
  }

  @Test
  func unsubscribeAfterAServerErrorForgetsThePayload() async throws {
    let host = await RealtimeTestHost()
    let channel = await host.client.channel("room")
    let join = try await subscribe(channel, on: host)
    try await channel.track(state: ["name": "ana"])
    var statuses = await channel.statusChanges().makeAsyncIterator()
    #expect(await statuses.next() == .subscribed)

    host.server?.send(
      RealtimeMessageV2(
        joinRef: join.ref, ref: nil, topic: channel.topic, event: ChannelEvent.error,
        payload: [:]
      )
    )
    #expect(await statuses.next() == .unsubscribed)
    await channel.unsubscribe()

    #expect(await channel.presence.trackedPayload == nil)
  }

  @Test
  func theFirstStateAfterARejoinReportsWhoLeft() async throws {
    let host = await RealtimeTestHost()
    let channel = await host.client.channel("room")
    var changes = await channel.presenceChanges().makeAsyncIterator()
    let firstJoin = try await subscribe(channel, on: host)
    sendPresenceState(
      ["u1": metas([("r1", "ana")]), "u2": metas([("r2", "bo")])], on: channel, host: host)
    _ = await changes.next()

    try await dropSocketAndRejoin(channel, after: firstJoin, on: host)
    sendPresenceState(["u1": metas([("r1", "ana")])], on: channel, host: host)

    let change = try #require(await changes.next())
    #expect(Set(change.leaves.keys) == ["u2"])
    #expect(change.leaves["u2"]?.ref == "r2")
  }

  @Test
  func heldDiffsAreDeliveredEvenWhenTheStateCannotBeDecoded() async throws {
    let host = await RealtimeTestHost()
    let channel = await host.client.channel("room")
    var changes = await channel.presenceChanges().makeAsyncIterator()
    try await subscribe(channel, on: host)

    sendPresenceDiff(joins: ["u2": metas([("r2", "bo")])], on: channel, host: host)
    sendPresenceState(["u1": "not a presence"], on: channel, host: host)

    let change = try #require(await changes.next())
    #expect(change.rawMessage.event == ChannelEvent.presenceDiff)
    #expect(Set(change.joins.keys) == ["u2"])
  }

  // MARK: - Rate window

  @Test
  func tracksInsideTheRateWindowCoalesceToTheNewest() async throws {
    let host = await RealtimeTestHost()
    let channel = await host.client.channel("room")
    try await subscribe(channel, on: host)

    try await channel.track(state: ["n": 1])
    try await channel.track(state: ["n": 2])
    try await channel.track(state: ["n": 3])
    _ = try await host.receive(where: Self.isTrack)

    await host.clock.advance(by: RealtimeChannel.presencePushInterval)

    await host.waitUntil { host.frames.filter(Self.isTrack).count == 2 }
    #expect(host.frames.filter(Self.isTrack).map(Self.trackedState) == [["n": 1], ["n": 3]])
  }

  @Test
  func anUnchangedPayloadIsNotSentAgain() async throws {
    let host = await RealtimeTestHost()
    let channel = await host.client.channel("room")
    try await subscribe(channel, on: host)

    // Whether the repeat lands inside or after the window, it must not go out.
    try await channel.track(state: ["n": 1])
    _ = try await host.receive(where: Self.isTrack)
    await host.clock.advance(by: RealtimeChannel.presencePushInterval)
    try await channel.track(state: ["n": 1])
    await host.clock.advance(by: RealtimeChannel.presencePushInterval)
    try await channel.track(state: ["n": 2])
    await host.clock.advance(by: RealtimeChannel.presencePushInterval)

    await host.waitUntil { host.frames.filter(Self.isTrack).count == 2 }
    #expect(host.frames.filter(Self.isTrack).map(Self.trackedState) == [["n": 1], ["n": 2]])
  }

  @Test
  func untrackInsideTheRateWindowReplacesThePendingTrack() async throws {
    let host = await RealtimeTestHost()
    let channel = await host.client.channel("room")
    try await subscribe(channel, on: host)

    try await channel.track(state: ["n": 1])
    try await channel.track(state: ["n": 2])
    try await channel.untrack()
    await host.clock.advance(by: RealtimeChannel.presencePushInterval)

    let untrack = try await host.receive { $0.payload["event"] == "untrack" }
    #expect(untrack.event == ChannelEvent.presence)
    #expect(host.frames.filter(Self.isTrack).map(Self.trackedState) == [["n": 1]])
  }

  // MARK: - Helpers

  @discardableResult
  private func subscribe(
    _ channel: RealtimeChannel, on host: RealtimeTestHost
  ) async throws -> RealtimeMessageV2 {
    async let subscribed: Void = channel.subscribe()
    let join = try await host.receive(event: ChannelEvent.join)
    host.confirmJoin(join)
    try await subscribed
    return join
  }

  /// Closes the socket from the server side, lets the client reconnect, runs
  /// `beforeConfirming` while the rejoin waits for the server, and confirms it.
  @discardableResult
  private func dropSocketAndRejoin(
    _ channel: RealtimeChannel, after join: RealtimeMessageV2, on host: RealtimeTestHost,
    beforeConfirming: () async throws -> Void = {}
  ) async throws -> RealtimeMessageV2 {
    var statuses = await channel.statusChanges().makeAsyncIterator()
    #expect(await statuses.next() == .subscribed)

    host.server?.close(code: 1006, reason: "network down")
    await host.waitUntil { host.statuses.last == .connecting }
    await host.clock.advance(by: .seconds(30))

    let rejoin = try await host.receive { $0.event == ChannelEvent.join && $0.ref != join.ref }
    try await beforeConfirming()
    host.confirmJoin(rejoin)
    while let status = await statuses.next(), status != .subscribed {}
    return rejoin
  }

  private func sendPresenceState(
    _ state: JSONObject, on channel: RealtimeChannel, host: RealtimeTestHost
  ) {
    host.server?.send(
      RealtimeMessageV2(
        joinRef: nil, ref: nil, topic: channel.topic, event: ChannelEvent.presenceState,
        payload: state
      )
    )
  }

  private func sendPresenceDiff(
    joins: JSONObject = [:], leaves: JSONObject = [:], on channel: RealtimeChannel,
    host: RealtimeTestHost
  ) {
    host.server?.send(
      RealtimeMessageV2(
        joinRef: nil, ref: nil, topic: channel.topic, event: ChannelEvent.presenceDiff,
        payload: ["joins": .object(joins), "leaves": .object(leaves)]
      )
    )
  }

  private func metas(_ entries: [(ref: String, name: String)]) -> JSONValue {
    .object([
      "metas": .array(
        entries.map { .object(["phx_ref": .string($0.ref), "name": .string($0.name)]) })
    ])
  }

  private static let isTrack: @Sendable (RealtimeMessageV2) -> Bool = {
    $0.event == ChannelEvent.presence && $0.payload["event"] == "track"
  }

  private static func trackedState(_ message: RealtimeMessageV2) -> JSONObject? {
    message.payload["payload"]?.objectValue
  }
}

extension JSONObject {
  /// `config.presence.enabled` of a `phx_join` payload.
  fileprivate var presenceEnabled: Bool? {
    self["config"]?.objectValue?["presence"]?.objectValue?["enabled"]?.boolValue
  }
}
