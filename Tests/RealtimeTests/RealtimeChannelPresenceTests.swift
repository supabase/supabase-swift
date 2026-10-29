//
//  RealtimeChannelPresenceTests.swift
//  RealtimeTests
//
//  Created by Guilherme Souza on 20/10/26.
//

import Clocks
import Foundation
import TestHelpers
import Testing

@testable import Realtime

@Suite
struct RealtimeChannelPresenceTests {
  @Test
  func presenceChangesReportJoinsAndLeavesPerKey() async throws {
    let host = await RealtimeTestHost()
    let channel = await host.client.channel("room")
    var changes = await channel.presenceChanges().makeAsyncIterator()
    try await subscribe(channel, on: host)

    sendPresenceState(["u1": metas([("r1", "ana")])], on: channel, host: host)
    let synced = try #require(await changes.next())
    #expect(synced.joins["u1"]?.map(\.payload) == [["name": "ana"]])
    #expect(synced.leaves.isEmpty)

    sendPresenceDiff(joins: ["u2": metas([("r2", "bo")])], on: channel, host: host)
    #expect(await changes.next()?.joins["u2"]?.map(\.ref) == ["r2"])

    sendPresenceDiff(leaves: ["u1": metas([("r1", "ana")])], on: channel, host: host)
    let left = try #require(await changes.next())
    #expect(left.leaves["u1"]?.map(\.ref) == ["r1"])
    #expect(left.joins.isEmpty)

    let state = await channel.presenceState
    #expect(Set(state.entries.keys) == ["u2"])
    #expect(state.entries["u2"]?.first?.payload == ["name": "bo"])
  }

  @Test
  func presenceStatesYieldTheCurrentStateThenEverySync() async throws {
    let host = await RealtimeTestHost()
    let channel = await host.client.channel("room")
    var states = await channel.presenceStates().makeAsyncIterator()
    #expect(await states.next() == PresenceState())
    try await subscribe(channel, on: host)

    sendPresenceState(["u1": metas([("r1", "ana")])], on: channel, host: host)
    #expect(await states.next().map { Set($0.entries.keys) } == ["u1"])

    sendPresenceDiff(joins: ["u2": metas([("r2", "bo")])], on: channel, host: host)
    #expect(await states.next().map { Set($0.entries.keys) } == ["u1", "u2"])
  }

  @Test
  func presenceStatesAloneEnablePresenceOnJoin() async throws {
    let host = await RealtimeTestHost()
    let channel = await host.client.channel("room")
    let states = await channel.presenceStates()

    async let subscribed: Void = channel.subscribe()
    let join = try await host.receive(event: ChannelEvent.join)
    host.confirmJoin(join)
    try await subscribed

    let presence = join.payload["config"]?.objectValue?["presence"]?.objectValue
    #expect(presence?["enabled"]?.boolValue == true)
    withExtendedLifetime(states) {}
  }

  @Test
  func diffBeforeTheFirstStateWaitsForIt() async throws {
    let host = await RealtimeTestHost()
    let channel = await host.client.channel("room")
    var states = await channel.presenceStates().makeAsyncIterator()
    _ = await states.next()
    try await subscribe(channel, on: host)

    sendPresenceDiff(joins: ["u2": metas([("r2", "bo")])], on: channel, host: host)
    sendPresenceState(["u1": metas([("r1", "ana")])], on: channel, host: host)

    #expect(await states.next().map { Set($0.entries.keys) } == ["u1", "u2"])
  }

  @Test
  func aRejoinReportsOnlyRealJoinsAndLeaves() async throws {
    let host = await RealtimeTestHost()
    let channel = await host.client.channel("room")
    var changes = await channel.presenceChanges().makeAsyncIterator()
    let firstJoin = try await subscribe(channel, on: host)
    sendPresenceState(
      ["u1": metas([("r1", "ana")]), "u2": metas([("r2", "bo")])], on: channel, host: host
    )
    _ = await changes.next()

    try await dropSocketAndRejoin(channel, after: firstJoin, on: host)
    #expect(Set(await channel.presenceState.entries.keys) == ["u1", "u2"])
    sendPresenceState(
      ["u1": metas([("r1", "ana")]), "u3": metas([("r3", "cy")])], on: channel, host: host
    )

    let change = try #require(await changes.next())
    #expect(Set(change.joins.keys) == ["u3"])
    #expect(Set(change.leaves.keys) == ["u2"])
    #expect(Set(await channel.presenceState.entries.keys) == ["u1", "u3"])
  }

  @Test
  func unsubscribeClearsTheStateAndReportsTheLeaves() async throws {
    let host = await RealtimeTestHost()
    let channel = await host.client.channel("room")
    var changes = await channel.presenceChanges().makeAsyncIterator()
    let join = try await subscribe(channel, on: host)
    sendPresenceState(["u1": metas([("r1", "ana")])], on: channel, host: host)
    _ = await changes.next()

    async let left: Void = channel.unsubscribe()
    _ = try await host.receive(event: ChannelEvent.leave)
    host.server?.send(
      RealtimeMessageV2(
        joinRef: join.ref, ref: nil, topic: channel.wireTopic, event: ChannelEvent.close,
        payload: [:]
      )
    )
    await left

    #expect(await changes.next()?.leaves["u1"]?.map(\.ref) == ["r1"])
    #expect(await channel.presenceState == PresenceState())
  }

  @Test
  func presenceMessagesFromAnotherJoinAreIgnored() async throws {
    let host = await RealtimeTestHost()
    let channel = await host.client.channel("room")
    var states = await channel.presenceStates().makeAsyncIterator()
    _ = await states.next()
    let join = try await subscribe(channel, on: host)

    sendPresenceState(["u9": metas([("r9", "stale")])], joinRef: "stale", on: channel, host: host)
    sendPresenceState(["u1": metas([("r1", "ana")])], joinRef: join.ref, on: channel, host: host)

    #expect(await states.next().map { Set($0.entries.keys) } == ["u1"])
  }

  @Test
  func presenceStatesSkipASyncThatChangesNothing() async throws {
    let host = await RealtimeTestHost()
    let channel = await host.client.channel("room")
    var states = await channel.presenceStates().makeAsyncIterator()
    _ = await states.next()
    try await subscribe(channel, on: host)
    sendPresenceState(["u1": metas([("r1", "ana")])], on: channel, host: host)
    _ = await states.next()

    sendPresenceState(["u1": metas([("r1", "ana")])], on: channel, host: host)
    sendPresenceDiff(joins: ["u2": metas([("r2", "bo")])], on: channel, host: host)

    #expect(await states.next().map { Set($0.entries.keys) } == ["u1", "u2"])
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
    await host.waitUntil { host.statuses.last == .reconnecting }
    // The first reconnect waits at most the base delay. Going further would also time out the
    // rejoin, so the join confirmed below would no longer be the current one. The first wait of
    // the default backoff is at most 1 s.
    await host.clock.advance(by: .seconds(1))

    let rejoin = try await host.receive { $0.event == ChannelEvent.join && $0.ref != join.ref }
    host.confirmJoin(rejoin)
    while let status = await statuses.next(), status != .subscribed {}
  }

  private func sendPresenceState(
    _ state: JSONObject, joinRef: String? = nil, on channel: RealtimeChannel,
    host: RealtimeTestHost
  ) {
    host.server?.send(
      RealtimeMessageV2(
        joinRef: joinRef, ref: nil, topic: channel.wireTopic, event: ChannelEvent.presenceState,
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
        joinRef: nil, ref: nil, topic: channel.wireTopic, event: ChannelEvent.presenceDiff,
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
