//
//  ChannelStateTests.swift
//  RealtimeTests
//

import Foundation
import Testing

@testable import Realtime

@Suite(.timeLimit(.minutes(1)))
struct ChannelStateTests {
  let tableA = PostgresJoinConfig(event: .all, schema: "public", table: "a")
  let tableB = PostgresJoinConfig(event: .all, schema: "public", table: "b")
  let channelID = ChannelID(rawValue: 1)

  func makeState() -> ChannelState {
    let client = RealtimeClient(
      url: URL(string: "https://localhost:54321/realtime/v1")!,
      options: RealtimeClientOptions(handleAppLifecycle: false))
    return ChannelState(
      handle: RealtimeChannel(
        id: channelID, topic: "room", configuration: RealtimeChannelConfiguration(),
        client: client))
  }

  func id(_ rawValue: UInt64) -> StreamID {
    StreamID(rawValue: rawValue, channel: channelID)
  }

  func collect<Element: Sendable>(_ stream: AsyncStream<Element>) async -> [Element] {
    await stream.reduce(into: []) { $0.append($1) }
  }

  func change(table: String) throws -> PostgresChange {
    try PostgresChange(payload: [
      "type": "INSERT", "schema": "public", "table": .string(table),
      "commit_timestamp": "2026-10-29T10:00:00.000Z", "columns": [], "errors": .null,
      "record": ["id": 1],
    ])
  }

  @Test
  func joinSnapshotKeepsBindingRegistrationOrder() {
    let state = makeState()
    let changesB = state.addPostgresStream(id(1), tableB, onTermination: {})
    let changesA = state.addPostgresStream(id(2), tableA, onTermination: {})

    #expect(state.joinSnapshot.bindings == [tableB, tableA])

    state.removeStream(id(1))

    #expect(state.joinSnapshot.bindings == [tableA])
    withExtendedLifetime((changesA, changesB)) {}
  }

  @Test
  func presenceIsEnabledWhileAPresenceStreamIsOpen() {
    let state = makeState()
    #expect(!state.joinSnapshot.presenceEnabled)

    let states = state.presenceStates.subscribe(id(1), onTermination: {})
    #expect(state.joinSnapshot.presenceEnabled)

    state.removeStream(id(1))
    #expect(!state.joinSnapshot.presenceEnabled)

    let changes = state.presenceChanges.subscribe(id(2), onTermination: {})
    #expect(state.joinSnapshot.presenceEnabled)
    withExtendedLifetime((states, changes)) {}
  }

  @Test
  func removeStreamReportsOnlyPostgresBindings() {
    let state = makeState()
    let changes = state.addPostgresStream(id(1), tableA, onTermination: {})
    let events = state.events.subscribe(id(2), onTermination: {})

    #expect(!state.removeStream(id(2)))
    #expect(state.removeStream(id(1)))
    #expect(!state.removeStream(id(1)))
    #expect(state.events.count == 0)
    withExtendedLifetime((changes, events)) {}
  }

  @Test
  func postgresChangeGoesOnlyToMatchingBindings() async throws {
    let state = makeState()
    let changesA = state.addPostgresStream(id(1), tableA, onTermination: {})
    let changesB = state.addPostgresStream(id(2), tableB, onTermination: {})
    let change = try change(table: "b")

    state.deliver(.postgres(PostgresDelivery(change: change, matched: [tableB])))
    state.finishAll()

    #expect(await collect(changesA).isEmpty)
    #expect(await collect(changesB) == [change])
  }

  @Test
  func deliveryReachesTheMatchingFanouts() async throws {
    let state = makeState()
    let events = state.events.subscribe(id(1), onTermination: {})
    let broadcasts = state.broadcasts.subscribe(id(2), onTermination: {})
    let presenceChanges = state.presenceChanges.subscribe(id(3), onTermination: {})
    let presenceStates = state.presenceStates.subscribe(id(4), onTermination: {})
    let message = try #require(
      BroadcastMessage(
        RealtimeMessage(
          joinRef: nil, ref: nil, topic: "realtime:room", event: "broadcast",
          payload: ["type": "broadcast", "event": "ping", "payload": ["a": 1]])))
    let presenceState = PresenceState(entries: ["u": []])
    let presenceChange = PresenceChange(joins: ["u": []], leaves: [:])

    state.deliver(.event(.resubscribed))
    state.deliver(.broadcast(message))
    state.deliver(.presence(presenceChange, presenceState))
    state.finishAll()

    #expect(await collect(events) == [.resubscribed])
    #expect(await collect(broadcasts) == [message])
    #expect(await collect(presenceChanges) == [presenceChange])
    #expect(await collect(presenceStates) == [PresenceState(), presenceState])
  }

  @Test
  func finishAllEndsEveryStreamAndSpendsTheState() async {
    let state = makeState()
    let status = state.status.subscribe(id(1), onTermination: {})
    let changes = state.addPostgresStream(id(2), tableA, onTermination: {})

    state.finishAll()

    let statuses = await collect(status)
    #expect(statuses.count == 1 && statuses[0].isSame(as: .unsubscribed))
    #expect(await collect(changes).isEmpty)
    #expect(state.joinSnapshot.bindings.isEmpty)
    #expect(await collect(state.addPostgresStream(id(3), tableA, onTermination: {})).isEmpty)
    #expect(state.joinSnapshot.bindings.isEmpty)
  }

  @Test
  func releasingChannelStateEndsEveryStream() async {
    var state: ChannelState? = makeState()
    let status = state!.status.subscribe(id(1), onTermination: {})
    let events = state!.events.subscribe(id(2), onTermination: {})
    let broadcasts = state!.broadcasts.subscribe(id(3), onTermination: {})
    let presenceChanges = state!.presenceChanges.subscribe(id(4), onTermination: {})
    let presenceStates = state!.presenceStates.subscribe(id(5), onTermination: {})
    let changes = state!.addPostgresStream(id(6), tableA, onTermination: {})

    state = nil

    let statuses = await collect(status)
    #expect(statuses.count == 1 && statuses[0].isSame(as: .unsubscribed))
    #expect(await collect(events).isEmpty)
    #expect(await collect(broadcasts).isEmpty)
    #expect(await collect(presenceChanges).isEmpty)
    #expect(await collect(presenceStates) == [PresenceState()])
    #expect(await collect(changes).isEmpty)
  }
}
