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
    _ = await changes.next()
    #expect(Set(await channel.presence.state.entries.keys) == ["u2"])
  }

  @Test
  func diffBeforeTheFirstStateWaitsForIt() async throws {
    let host = await RealtimeTestHost()
    let channel = await host.client.channel("room")
    var changes = await channel.presenceChanges().makeAsyncIterator()
    try await subscribe(channel, on: host)

    sendPresenceDiff(joins: ["u2": metas([("r2", "bo")])], on: channel, host: host)
    _ = await changes.next()
    #expect(await channel.presence.state.entries.isEmpty)

    sendPresenceState(["u1": metas([("r1", "ana")])], on: channel, host: host)
    _ = await changes.next()
    #expect(Set(await channel.presence.state.entries.keys) == ["u1", "u2"])
  }

  @Test
  func aRejoinWaitsForItsOwnFirstState() async throws {
    let host = await RealtimeTestHost()
    let channel = await host.client.channel("room")
    var changes = await channel.presenceChanges().makeAsyncIterator()
    let firstJoin = try await subscribe(channel, on: host)
    sendPresenceState(["u1": metas([("r1", "ana")])], on: channel, host: host)
    _ = await changes.next()

    try await dropSocketAndRejoin(channel, after: firstJoin, on: host)
    sendPresenceDiff(joins: ["u2": metas([("r2", "bo")])], on: channel, host: host)
    _ = await changes.next()
    #expect(await channel.presence.state.entries.isEmpty)

    sendPresenceState(["u3": metas([("r3", "cy")])], on: channel, host: host)
    _ = await changes.next()
    #expect(Set(await channel.presence.state.entries.keys) == ["u2", "u3"])
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
    // The first reconnect waits at most the base delay. Going further would also time out the
    // rejoin, so the join confirmed below would no longer be the current one.
    await host.clock.advance(by: RealtimeClientOptions.defaultReconnectDelay)

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
