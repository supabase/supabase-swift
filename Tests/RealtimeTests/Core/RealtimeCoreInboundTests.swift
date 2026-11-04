//
//  RealtimeCoreInboundTests.swift
//  RealtimeTests
//

import ConcurrencyExtras
import Foundation
import Helpers
import Logging
import TestHelpers
import Testing

@testable import Realtime

/// How ``RealtimeCore`` routes inbound frames to a channel's streams: broadcasts, Postgres
/// changes, and presence.
@Suite
struct RealtimeCoreInboundTests {
  typealias Event = RealtimeCore.Event
  typealias Effect = RealtimeCore.Effect

  static let topic = "room"
  static let wireTopic = "realtime:room"
  static let messages = PostgresJoinConfig(event: .insert, schema: "public", table: "messages")
  static let users = PostgresJoinConfig(event: .all, schema: "public", table: "users")
  static let noStreams = JoinSnapshot(bindings: [], presenceEnabled: false)

  @Test
  func broadcastDelivered() throws {
    var harness = Self.subscribed()
    let frame = Self.frame(
      event: "broadcast",
      payload: ["type": "broadcast", "event": "cursor", "payload": ["x": 1]])
    let broadcast = try #require(BroadcastMessage(frame))
    #expect(broadcast.event == "cursor")

    #expect(harness.send(.frame(frame)) == [.deliver(.room, .broadcast(broadcast))])
  }

  @Test
  func binaryBroadcastDelivered() {
    var harness = Self.subscribed()
    let decoded = DecodedBroadcast(
      topic: Self.wireTopic, event: "cursor", payload: .binary(Data([1, 2, 3])))

    #expect(
      harness.send(.binaryBroadcast(decoded)) == [
        .deliver(.room, .broadcast(BroadcastMessage(decoded)))
      ])
    #expect(
      harness.send(
        .binaryBroadcast(
          DecodedBroadcast(topic: "realtime:other", event: "cursor", payload: .json([:]))))
        == [])
  }

  @Test
  func postgresChangeDeliveredWithMatchedConfigs() throws {
    var configuration = RealtimeChannelConfiguration()
    configuration.postgresChanges.waitForSubscription = true
    var harness = CoreHarness.connected()
    _ = harness.send(
      .subscribe(
        channel: .room, topic: Self.topic, configuration: configuration, waiter: harness.waiter(),
        snapshot: JoinSnapshot(bindings: [Self.messages, Self.users], presenceEnabled: false)))
    _ = harness.send(
      .frame(
        Self.reply(
          ref: "1",
          response: [
            "postgres_changes": [
              ["event": "INSERT", "schema": "public", "table": "messages", "id": 7],
              ["event": "*", "schema": "public", "table": "users", "id": 8],
            ]
          ])))
    #expect(harness.core.channels[.room]?.phase == .subscribed(joinRef: "1"))
    let data: JSONObject = [
      "type": "INSERT", "schema": "public", "table": "messages",
      "commit_timestamp": "2026-10-29T10:00:00.000Z", "columns": [], "errors": .null,
      "record": ["id": 1],
    ]

    let effects = harness.send(
      .frame(Self.frame(event: "postgres_changes", payload: ["ids": [7], "data": .object(data)])))

    let change = try PostgresChange(payload: data)
    guard case .deliver(.room, .postgres(let delivery))? = effects.first, effects.count == 1
    else {
      Issue.record("Expected one Postgres delivery, got \(effects)")
      return
    }
    #expect(delivery.change == change)
    #expect(delivery.matched.map(\.id) == [7])
    #expect(delivery.matched.map(\.table) == ["messages"])
  }

  @Test
  func presenceStateThenDiff() throws {
    var harness = Self.subscribed(presence: true)
    var expected = PresenceTracker()
    expected.waitForNextState()

    // A diff before the join's first state waits for it.
    #expect(harness.send(.frame(Self.frame(event: "presence_diff", payload: Self.bobJoins))) == [])
    let queued = expected.applyDiff(Self.bobJoins)
    #expect(queued == nil)

    let stateChange = expected.applyState(Self.aliceState)
    #expect(Set(stateChange.joins.keys) == ["alice", "bob"])
    #expect(
      harness.send(.frame(Self.frame(event: "presence_state", payload: Self.aliceState))) == [
        .deliver(.room, .presence(stateChange, expected.state))
      ])

    let applied = expected.applyDiff(Self.aliceLeaves)
    let leave = try #require(applied)
    #expect(
      harness.send(.frame(Self.frame(event: "presence_diff", payload: Self.aliceLeaves))) == [
        .deliver(.room, .presence(leave, expected.state))
      ])
    #expect(harness.core.channels[.room]?.presence.state == expected.state)
  }

  @Test
  func presenceForStaleJoinRefIgnored() {
    var harness = Self.subscribed(presence: true)

    #expect(
      harness.send(
        .frame(Self.frame(joinRef: "9", event: "presence_state", payload: Self.aliceState)))
        == [])
    #expect(harness.core.channels[.room]?.presence.state == PresenceState())

    _ = harness.send(.frame(Self.frame(event: "presence_state", payload: Self.aliceState)))
    #expect(
      harness.send(
        .frame(Self.frame(joinRef: "9", event: "presence_diff", payload: Self.bobJoins))) == [])
    // A diff without a join_ref always applies.
    let applied = harness.send(
      .frame(Self.frame(joinRef: nil, event: "presence_diff", payload: Self.bobJoins)))
    #expect(applied.count == 1)
    #expect(
      harness.core.channels[.room]?.presence.state.entries.keys.sorted() == ["alice", "bob"])
  }

  @Test
  func frameForUnknownTopicDropped() {
    var harness = Self.subscribed()
    let payload: JSONObject = ["type": "broadcast", "event": "cursor", "payload": [:]]

    #expect(
      harness.send(
        .frame(
          RealtimeMessage(
            joinRef: nil, ref: nil, topic: "realtime:other", event: "broadcast",
            payload: payload))) == [])
    #expect(
      harness.send(
        .frame(
          RealtimeMessage(
            joinRef: nil, ref: nil, topic: "room", event: "broadcast", payload: payload)))
        == [])
  }

  @Test
  func undecodablePayloadIsLoggedAndDropped() {
    let logs = LockIsolated<[String]>([])
    let logger = Logger(label: "RealtimeCoreInboundTests") { _ in CapturingLogHandler(logs: logs) }
    var harness = CoreHarness.connected(logger: logger)
    _ = harness.send(
      .subscribe(
        channel: .room, topic: Self.topic, configuration: RealtimeChannelConfiguration(),
        waiter: harness.waiter(), snapshot: Self.noStreams))
    _ = harness.send(.frame(Self.reply(ref: "1")))
    logs.setValue([])

    #expect(
      harness.send(.frame(Self.frame(event: "broadcast", payload: ["payload": ["x": 1]]))) == [])
    #expect(
      harness.send(.frame(Self.frame(event: "postgres_changes", payload: ["data": "nope"]))) == [])
    #expect(
      harness.send(.frame(Self.frame(event: "postgres_changes", payload: ["data": [:]]))) == [])

    #expect(logs.value.count == 3)
    #expect(logs.value.allSatisfy { $0.contains("'room'") })
  }

  // MARK: Helpers

  static let aliceState: JSONObject = [
    "alice": ["metas": [["phx_ref": "a1", "name": "alice"]]]
  ]
  static let bobJoins: JSONObject = [
    "joins": ["bob": ["metas": [["phx_ref": "b1", "name": "bob"]]]], "leaves": [:],
  ]
  static let aliceLeaves: JSONObject = [
    "joins": [:], "leaves": ["alice": ["metas": [["phx_ref": "a1", "name": "alice"]]]],
  ]

  /// A connected harness whose channel joined with ref `"1"`. It used waiter id 1.
  static func subscribed(presence: Bool = false) -> CoreHarness {
    var harness = CoreHarness.connected()
    let room = harness.channel()
    _ = harness.send(
      .subscribe(
        channel: room, topic: topic, configuration: RealtimeChannelConfiguration(),
        waiter: harness.waiter(),
        snapshot: JoinSnapshot(bindings: [], presenceEnabled: presence)))
    _ = harness.send(.frame(reply(ref: "1")))
    return harness
  }

  static func frame(
    joinRef: Ref? = "1", event: String, payload: JSONObject
  ) -> RealtimeMessage {
    RealtimeMessage(joinRef: joinRef, ref: nil, topic: wireTopic, event: event, payload: payload)
  }

  static func reply(ref: Ref, response: JSONObject = [:]) -> RealtimeMessage {
    RealtimeMessage(
      joinRef: ref, ref: ref, topic: wireTopic, event: "phx_reply",
      payload: ["status": "ok", "response": .object(response)])
  }
}

/// Keeps every message logged at `debug` or above.
private struct CapturingLogHandler: LogHandler {
  let logs: LockIsolated<[String]>
  var metadata: Logger.Metadata = [:]
  var logLevel: Logger.Level = .debug

  subscript(metadataKey key: String) -> Logger.Metadata.Value? {
    get { metadata[key] }
    set { metadata[key] = newValue }
  }

  func log(event: LogEvent) {
    logs.withValue { $0.append(event.message.description) }
  }
}
