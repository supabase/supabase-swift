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

  @Test
  func aLeaveHeldBeforeTheFirstStateIsDeliveredOnce() async throws {
    let host = await RealtimeTestHost()
    let channel = await host.client.channel("room")
    var changes = await channel.presenceChanges().makeAsyncIterator()
    try await subscribe(channel, on: host)

    sendPresenceDiff(leaves: ["u2": metas([("r2", "bo")])], on: channel, host: host)
    sendPresenceState(["u1": metas([("r1", "ana")])], on: channel, host: host)

    let state = try #require(await changes.next())
    let diff = try #require(await changes.next())
    #expect(state.leaves.isEmpty)
    #expect(Set(diff.leaves.keys) == ["u2"])
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

  // MARK: - Rejoin

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
  func aLeaveHeldAfterARejoinIsNotAlsoReportedByTheState() async throws {
    let host = await RealtimeTestHost()
    let channel = await host.client.channel("room")
    var changes = await channel.presenceChanges().makeAsyncIterator()
    let firstJoin = try await subscribe(channel, on: host)
    sendPresenceState(
      ["u1": metas([("r1", "ana")]), "u2": metas([("r2", "bo")])], on: channel, host: host)
    _ = await changes.next()

    try await dropSocketAndRejoin(channel, after: firstJoin, on: host)
    sendPresenceDiff(leaves: ["u2": metas([("r2", "bo")])], on: channel, host: host)
    sendPresenceState(["u1": metas([("r1", "ana")])], on: channel, host: host)

    let state = try #require(await changes.next())
    let diff = try #require(await changes.next())
    #expect(state.leaves.isEmpty)
    #expect(Set(diff.leaves.keys) == ["u2"])
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

  /// Closes the socket from the server side, lets the client reconnect, and confirms the rejoin.
  private func dropSocketAndRejoin(
    _ channel: RealtimeChannel, after join: RealtimeMessageV2, on host: RealtimeTestHost
  ) async throws {
    var statuses = await channel.statusChanges().makeAsyncIterator()
    #expect(await statuses.next() == .subscribed)

    host.server?.close(code: 1006, reason: "network down")
    await host.waitUntil { host.statuses.last == .connecting }
    await host.clock.advance(by: .seconds(30))

    let rejoin = try await host.receive { $0.event == ChannelEvent.join && $0.ref != join.ref }
    host.confirmJoin(rejoin)
    while let status = await statuses.next(), status != .subscribed {}
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
}
