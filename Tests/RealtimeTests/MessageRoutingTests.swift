//
//  MessageRoutingTests.swift
//  Realtime
//
//  Created by Guilherme Souza on 23/10/26.
//

import Foundation
import Testing

@testable import Realtime

@Suite
struct MessageRoutingTests {
  let topic = "realtime:public:messages"
  let commitTimestamp = Date(timeIntervalSince1970: 1_703_592_000)
  let commitTimestampJSON: JSONValue
  let messagesChange = PostgresJoinConfig(event: .all, schema: "public", table: "messages")

  init() throws {
    commitTimestampJSON = try JSONValue(commitTimestamp)
  }

  // MARK: - Events that reach no stream

  @Test(arguments: [
    "not_a_channel_event", ChannelEvent.reply, ChannelEvent.close, ChannelEvent.error,
  ])
  func eventsWithoutStreamsRouteNowhere(event: String) throws {
    let routed = try route(
      message(event: event, payload: ["status": "ok", "event": "x"]),
      bindings: everyBinding,
      serverChanges: [serverChange(id: 1)]
    )

    #expect(routed?.listeners == nil)
  }

  // MARK: - System

  @Test(arguments: [["status": "ok"], ["status": "error"], [:]] as [JSONObject])
  func systemReachesEverySystemStream(payload: JSONObject) throws {
    let sent = message(event: ChannelEvent.system, payload: payload)

    let routed = try routeMessage(
      sent,
      bindings: [.system, .broadcast(event: "*"), .system, .presence],
      serverChanges: []
    )

    #expect(routed.listeners == [0, 2])
    guard case .system(let received) = routed.delivery else {
      Issue.record("Expected .system, got \(routed.delivery)")
      return
    }
    #expect(received == sent)
  }

  // MARK: - Broadcast

  @Test
  func broadcastReachesStreamsForItsEventAndTheWildcard() throws {
    let payload: JSONObject = ["event": "Message", "payload": ["body": "hi"], "type": "broadcast"]

    let routed = try routeMessage(
      message(event: ChannelEvent.broadcast, payload: payload),
      bindings: [
        .broadcast(event: "message"),
        .broadcast(event: "other"),
        .broadcast(event: "*"),
        .broadcastData(event: "message"),
        .system,
      ],
      serverChanges: []
    )

    #expect(routed.listeners == [0, 2])
    guard case .broadcast(let json) = routed.delivery else {
      Issue.record("Expected .broadcast, got \(routed.delivery)")
      return
    }
    #expect(json == payload)
  }

  @Test
  func broadcastWithoutEventThrowsDecoding() {
    #expect {
      try route(
        message(event: ChannelEvent.broadcast, payload: ["payload": ["body": "hi"]]),
        bindings: [.broadcast(event: "*")],
        serverChanges: []
      )
    } throws: { ($0 as? RealtimeError)?.kind == .decoding }
  }

  // MARK: - Binary broadcast

  @Test
  func binaryJSONBroadcastReachesBroadcastStreamsInTextShape() {
    let broadcast = DecodedBroadcast(
      topic: topic,
      event: "evt",
      payload: .json(["key": "value"])
    )

    let routed = route(
      broadcast,
      bindings: [.broadcastData(event: "evt"), .broadcast(event: "EVT"), .broadcast(event: "x")]
    )

    #expect(routed.listeners == [1])
    guard case .broadcast(let json) = routed.delivery else {
      Issue.record("Expected .broadcast, got \(routed.delivery)")
      return
    }
    #expect(json == ["event": "evt", "payload": ["key": "value"], "type": "broadcast"])
  }

  @Test
  func binaryJSONBroadcastForwardsFrameMetadataAsMeta() {
    let broadcast = DecodedBroadcast(
      topic: topic,
      event: "INSERT",
      meta: ["id": "0b8a1e2c-77c4-4f1b-9d2a-3f5e6a7b8c9d", "replayed": true],
      payload: .json([:])
    )

    let routed = route(broadcast, bindings: [.broadcast(event: "*")])

    guard case .broadcast(let json) = routed.delivery else {
      Issue.record("Expected .broadcast, got \(routed.delivery)")
      return
    }
    #expect(json["meta"] == ["id": "0b8a1e2c-77c4-4f1b-9d2a-3f5e6a7b8c9d", "replayed": true])
  }

  @Test
  func binaryDataBroadcastReachesBroadcastDataStreams() {
    let bytes = Data([0xCA, 0xFE, 0xBA, 0xBE])
    let broadcast = DecodedBroadcast(topic: topic, event: "bin", payload: .binary(bytes))

    let routed = route(
      broadcast,
      bindings: [
        .broadcast(event: "bin"), .broadcastData(event: "*"), .broadcastData(event: "BIN"),
      ]
    )

    #expect(routed.listeners == [1, 2])
    guard case .broadcastData(let data) = routed.delivery else {
      Issue.record("Expected .broadcastData, got \(routed.delivery)")
      return
    }
    #expect(data == bytes)
  }

  @Test
  func binaryDataBroadcastWithoutDataStreamRoutesNowhere() {
    let broadcast = DecodedBroadcast(topic: topic, event: "bin", payload: .binary(Data([1])))

    #expect(route(broadcast, bindings: [.broadcast(event: "*")]).listeners.isEmpty)
  }

  // MARK: - Postgres changes

  @Test
  func postgresChangesWithoutDataThrowsDecoding() {
    #expect {
      try routePostgres(["ids": [1]])
    } throws: { ($0 as? RealtimeError)?.kind == .decoding }
  }

  @Test
  func postgresInsertBecomesInsertAction() throws {
    let action = try #require(
      routePostgres([
        "ids": [1],
        "data": [
          "type": "INSERT",
          "record": ["id": 1, "body": "hello"],
          "columns": [["name": "id", "type": "int4"], ["name": "body", "type": "text"]],
          "commit_timestamp": commitTimestampJSON,
        ],
      ]).first
    )

    guard case .insert(let insert) = action else {
      Issue.record("Expected .insert, got \(action)")
      return
    }
    #expect(insert.record == ["id": 1, "body": "hello"])
    #expect(insert.commitTimestamp == commitTimestamp)
    #expect(
      insert.columns == [Column(name: "id", type: "int4"), Column(name: "body", type: "text")])
  }

  @Test
  func postgresUpdateBecomesUpdateActionWithBothRecords() throws {
    let action = try #require(
      routePostgres([
        "ids": [1],
        "data": [
          "type": "UPDATE",
          "record": ["id": 1, "body": "new"],
          "old_record": ["id": 1, "body": "old"],
          "columns": [["name": "body", "type": "text"]],
          "commit_timestamp": commitTimestampJSON,
        ],
      ]).first
    )

    guard case .update(let update) = action else {
      Issue.record("Expected .update, got \(action)")
      return
    }
    #expect(update.record == ["id": 1, "body": "new"])
    #expect(update.oldRecord == ["id": 1, "body": "old"])
  }

  @Test
  func postgresUpdateWithoutRecordsFallsBackToEmptyObjects() throws {
    let action = try #require(
      routePostgres([
        "ids": [1],
        "data": [
          "type": "UPDATE",
          "columns": [["name": "body", "type": "text"]],
          "commit_timestamp": commitTimestampJSON,
        ],
      ]).first
    )

    guard case .update(let update) = action else {
      Issue.record("Expected .update, got \(action)")
      return
    }
    #expect(update.record.isEmpty)
    #expect(update.oldRecord.isEmpty)
  }

  @Test
  func postgresDeleteBecomesDeleteAction() throws {
    let action = try #require(
      routePostgres([
        "ids": [1],
        "data": [
          "type": "DELETE",
          "old_record": ["id": 1],
          "columns": [["name": "id", "type": "int4"]],
          "commit_timestamp": commitTimestampJSON,
        ],
      ]).first
    )

    guard case .delete(let delete) = action else {
      Issue.record("Expected .delete, got \(action)")
      return
    }
    #expect(delete.oldRecord == ["id": 1])
  }

  @Test
  func postgresUnknownTypeThrowsDecoding() {
    #expect {
      try routePostgres([
        "ids": [1],
        "data": ["type": "TRUNCATE", "columns": [], "commit_timestamp": commitTimestampJSON],
      ])
    } throws: { ($0 as? RealtimeError)?.kind == .decoding }
  }

  @Test
  func postgresMalformedDataThrows() {
    #expect(throws: (any Error).self) {
      try routePostgres(["ids": [1], "data": ["type": "INSERT"]])
    }
  }

  @Test
  func postgresChangeWithoutIdsReachesNoStream() throws {
    #expect(try routePostgres(["data": insertData]).isEmpty)
  }

  @Test
  func postgresChangeReachesOnlyStreamsMatchingTheServerBindingsItNames() throws {
    let users = PostgresJoinConfig(event: .insert, schema: "public", table: "users")
    let ordersFiltered = PostgresJoinConfig(
      event: .update, schema: "public", table: "orders", filter: "id=eq.1")
    let orders = PostgresJoinConfig(event: .update, schema: "public", table: "orders")

    let routed = try routeMessage(
      message(
        event: ChannelEvent.postgresChanges, payload: ["ids": [11, 13], "data": insertData]),
      bindings: [
        .postgres(users), .postgres(ordersFiltered), .broadcast(event: "*"), .postgres(orders),
      ],
      serverChanges: [
        serverChange(users, id: 11),
        serverChange(ordersFiltered, id: 12),
        serverChange(orders, id: 13),
      ]
    )

    #expect(routed.listeners == [0, 3])
  }

  @Test
  func postgresMatchIgnoresServerIdAndSelect() throws {
    let client = PostgresJoinConfig(
      event: .insert, schema: "public", table: "users", filter: "id=1", select: ["id", "name"])
    let server = PostgresJoinConfig(
      event: .insert, schema: "public", table: "users", filter: "id=1", id: 2)

    #expect(try routePostgres(bindings: [.postgres(client)], serverChanges: [server]).count == 1)
  }

  @Test
  func postgresWildcardStreamMatchesAServerBindingForOneEvent() throws {
    let client = PostgresJoinConfig(event: .all, schema: "public", table: "users", filter: "id=1")
    let server = PostgresJoinConfig(
      event: .insert, schema: "public", table: "users", filter: "id=1", id: 2)

    #expect(try routePostgres(bindings: [.postgres(client)], serverChanges: [server]).count == 1)
  }

  @Test
  func postgresStreamForOneEventDoesNotMatchAServerBindingForAnother() throws {
    let client = PostgresJoinConfig(
      event: .update, schema: "public", table: "users", filter: "id=1")
    let server = PostgresJoinConfig(
      event: .insert, schema: "public", table: "users", filter: "id=1", id: 2)

    #expect(try routePostgres(bindings: [.postgres(client)], serverChanges: [server]).isEmpty)
  }

  // MARK: - Presence

  @Test
  func presenceDiffReachesEveryPresenceStreamWithJoinsAndLeaves() throws {
    let routed = try routeMessage(
      message(
        event: ChannelEvent.presenceDiff,
        payload: [
          "joins": ["user-1": ["metas": [["phx_ref": "ref-1", "name": "ana"]]]],
          "leaves": ["user-2": ["metas": [["phx_ref": "ref-2"]]]],
        ]
      ),
      bindings: [.presence, .system, .presence],
      serverChanges: []
    )

    #expect(routed.listeners == [0, 2])
    guard case .presence(let action) = routed.delivery else {
      Issue.record("Expected .presence, got \(routed.delivery)")
      return
    }
    #expect(action.joins.keys.sorted() == ["user-1"])
    #expect(action.joins["user-1"]?.ref == "ref-1")
    #expect(action.joins["user-1"]?.state["name"]?.stringValue == "ana")
    #expect(action.leaves.keys.sorted() == ["user-2"])
    #expect(action.leaves["user-2"]?.ref == "ref-2")
  }

  @Test
  func presenceDiffWithoutJoinsOrLeavesIsAnEmptyAction() throws {
    let routed = try routeMessage(
      message(event: ChannelEvent.presenceDiff), bindings: [.presence], serverChanges: []
    )

    guard case .presence(let action) = routed.delivery else {
      Issue.record("Expected .presence, got \(routed.delivery)")
      return
    }
    #expect(action.joins.isEmpty)
    #expect(action.leaves.isEmpty)
  }

  @Test
  func presenceDiffWithMalformedPresenceThrows() {
    #expect(throws: (any Error).self) {
      try route(
        message(event: ChannelEvent.presenceDiff, payload: ["joins": ["user-1": ["metas": []]]]),
        bindings: [.presence],
        serverChanges: []
      )
    }
  }

  @Test
  func presenceStateBecomesJoinsOnly() throws {
    let routed = try routeMessage(
      message(
        event: ChannelEvent.presenceState,
        payload: ["user-1": ["metas": [["phx_ref": "ref-1", "name": "ana"]]]]
      ),
      bindings: [.presence],
      serverChanges: []
    )

    guard case .presence(let action) = routed.delivery else {
      Issue.record("Expected .presence, got \(routed.delivery)")
      return
    }
    #expect(action.joins["user-1"]?.ref == "ref-1")
    #expect(action.leaves.isEmpty)
  }

  @Test
  func presenceStateWithMalformedPresenceThrows() {
    #expect(throws: (any Error).self) {
      try route(
        message(event: ChannelEvent.presenceState, payload: ["user-1": "not-a-presence"]),
        bindings: [.presence],
        serverChanges: []
      )
    }
  }

  // MARK: - Helpers

  private var everyBinding: [ChannelBinding] {
    [
      .broadcast(event: "*"), .broadcastData(event: "*"), .postgres(messagesChange), .presence,
      .system, .status,
    ]
  }

  private var insertData: JSONValue {
    [
      "type": "INSERT",
      "record": ["id": 1],
      "columns": [["name": "id", "type": "int4"]],
      "commit_timestamp": commitTimestampJSON,
    ]
  }

  private func message(event: String, payload: JSONObject = [:]) -> RealtimeMessageV2 {
    RealtimeMessageV2(joinRef: nil, ref: nil, topic: topic, event: event, payload: payload)
  }

  private func serverChange(_ change: PostgresJoinConfig? = nil, id: Int) -> PostgresJoinConfig {
    var change = change ?? messagesChange
    change.id = id
    return change
  }

  private func routeMessage(
    _ message: RealtimeMessageV2, bindings: [ChannelBinding], serverChanges: [PostgresJoinConfig]
  ) throws -> ChannelRoute {
    try #require(try route(message, bindings: bindings, serverChanges: serverChanges))
  }

  private func routePostgres(_ payload: JSONObject) throws -> [AnyAction] {
    let routed = try routeMessage(
      message(event: ChannelEvent.postgresChanges, payload: payload),
      bindings: [.postgres(messagesChange)],
      serverChanges: [serverChange(id: 1)]
    )
    guard case .postgres(let action) = routed.delivery else { return [] }
    return routed.listeners.map { _ in action }
  }

  private func routePostgres(
    bindings: [ChannelBinding], serverChanges: [PostgresJoinConfig]
  ) throws -> [Int] {
    try routeMessage(
      message(event: ChannelEvent.postgresChanges, payload: ["ids": [2], "data": insertData]),
      bindings: bindings,
      serverChanges: serverChanges
    ).listeners
  }
}
