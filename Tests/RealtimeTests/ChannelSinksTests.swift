//
//  ChannelSinksTests.swift
//  Realtime
//

import Testing

@testable import Realtime

@Suite(.timeLimit(.minutes(1)))
struct ChannelSinksTests {
  let tableA = PostgresJoinConfig(event: .all, schema: "public", table: "a")
  let tableB = PostgresJoinConfig(event: .all, schema: "public", table: "b")

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
  func postgresStreamRegistersBindingInOrderAndRemovesOnTermination() async {
    let sinks = ChannelSinks()
    let changesA = sinks.postgresChanges(tableA)
    let changesB = sinks.postgresChanges(tableB)

    #expect(sinks.bindings == [tableA, tableB])

    let consumer = Task { for await _ in changesA {} }
    consumer.cancel()
    await consumer.value

    #expect(sinks.bindings == [tableB])
    withExtendedLifetime(changesB) {}
  }

  @Test
  func postgresDeliveryReachesOnlyMatchedStreams() async throws {
    let sinks = ChannelSinks()
    let changesA = sinks.postgresChanges(tableA)
    let changesB = sinks.postgresChanges(tableB)
    let change = try change(table: "b")

    sinks.postgres.yield(PostgresDelivery(change: change, matched: [tableB]))
    sinks.finishAll()

    #expect(await collect(changesA) == [])
    #expect(await collect(changesB) == [change])
  }

  @Test
  func presenceListenerFlagFollowsSubscribers() async {
    let sinks = ChannelSinks()
    #expect(!sinks.hasPresenceListener)

    let states = sinks.presenceStates.subscribe()
    #expect(sinks.hasPresenceListener)

    let consumer = Task { for await _ in states {} }
    consumer.cancel()
    await consumer.value

    #expect(!sinks.hasPresenceListener)
  }

  @Test
  func finishAllEndsStreamsAndMarksSpent() async {
    let sinks = ChannelSinks()
    let status = sinks.status.subscribe()
    let events = sinks.events.subscribe()
    let broadcasts = sinks.broadcasts.subscribe()
    let presenceChanges = sinks.presenceChanges.subscribe()
    let presenceStates = sinks.presenceStates.subscribe()
    let changes = sinks.postgresChanges(tableA)

    sinks.finishAll()

    #expect(await collect(status).count == 1)
    #expect(await collect(events).isEmpty)
    #expect(await collect(broadcasts).isEmpty)
    #expect(await collect(presenceChanges).isEmpty)
    #expect(await collect(presenceStates) == [PresenceState()])
    #expect(await collect(changes).isEmpty)
    #expect(sinks.isSpent)
    #expect(sinks.bindings.isEmpty)
    #expect(await collect(sinks.broadcasts.subscribe()).isEmpty)
  }
}
