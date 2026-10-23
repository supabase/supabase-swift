//
//  JoinPayloadTests.swift
//  Realtime
//
//  Created by Guilherme Souza on 23/10/26.
//

import CustomDump
import Foundation
import Testing

@testable import Realtime

@Suite
struct JoinPayloadTests {
  let defaultConfig = RealtimeChannelConfig(
    broadcast: BroadcastJoinConfig(),
    presence: PresenceJoinConfig(),
    isPrivate: false
  )

  @Test
  func defaultConfigWithoutStreams() throws {
    let payload = try joinPayload(
      config: defaultConfig,
      bindings: [],
      accessToken: "token123",
      version: "realtime-swift/1.0"
    )

    expectNoDifference(
      payload,
      [
        "config": [
          "broadcast": ["ack": false, "self": false, "replication_ready": false],
          "presence": ["key": "", "enabled": false],
          "postgres_changes": [],
          "private": false,
        ],
        "access_token": "token123",
        "version": "realtime-swift/1.0",
      ]
    )
  }

  @Test
  func missingAccessTokenAndVersionAreOmitted() throws {
    let payload = try joinPayload(
      config: defaultConfig, bindings: [], accessToken: nil, version: nil
    )

    #expect(payload["access_token"] == nil)
    #expect(payload["version"] == nil)
    #expect(payload["config"] != nil)
  }

  @Test
  func customConfigValues() throws {
    let config = RealtimeChannelConfig(
      broadcast: BroadcastJoinConfig(
        acknowledgeBroadcasts: true,
        receiveOwnBroadcasts: true,
        replay: ReplayOption(since: 1_700_000_000_000, limit: 25),
        replicationReady: true
      ),
      presence: PresenceJoinConfig(key: "user123"),
      isPrivate: true
    )

    let payload = try joinPayload(config: config, bindings: [], accessToken: nil, version: nil)

    expectNoDifference(
      payload["config"],
      [
        "broadcast": [
          "ack": true,
          "self": true,
          "replay": ["since": 1_700_000_000_000, "limit": 25],
          "replication_ready": true,
        ],
        "presence": ["key": "user123", "enabled": false],
        "postgres_changes": [],
        "private": true,
      ]
    )
  }

  @Test
  func replayWithoutLimitOmitsLimit() throws {
    var config = defaultConfig
    config.broadcast.replay = ReplayOption(since: 42)

    let payload = try joinPayload(config: config, bindings: [], accessToken: nil, version: nil)

    #expect(payload["config"]?.objectValue?["broadcast"]?.objectValue?["replay"] == ["since": 42])
  }

  @Test
  func presenceStreamEnablesPresence() throws {
    let payload = try joinPayload(
      config: defaultConfig, bindings: [.broadcast(event: "x"), .presence], accessToken: nil,
      version: nil
    )

    #expect(
      payload["config"]?.objectValue?["presence"] == ["key": "", "enabled": true]
    )
  }

  @Test
  func streamsOtherThanPresenceLeavePresenceDisabled() throws {
    let payload = try joinPayload(
      config: defaultConfig,
      bindings: [.broadcast(event: "*"), .broadcastData(event: "*"), .system, .status],
      accessToken: nil,
      version: nil
    )

    #expect(payload["config"]?.objectValue?["presence"]?.objectValue?["enabled"] == false)
    #expect(payload["config"]?.objectValue?["postgres_changes"] == [])
  }

  @Test
  func postgresStreamsBecomePostgresChangesInRegistrationOrder() throws {
    let payload = try joinPayload(
      config: defaultConfig,
      bindings: [
        .postgres(PostgresJoinConfig(event: .update, schema: "public", table: "orders")),
        .presence,
        .postgres(
          PostgresJoinConfig(
            event: .insert, schema: "public", table: "users", filter: "id=eq.1",
            select: ["id", "first_name"]
          )
        ),
        .postgres(PostgresJoinConfig(event: .delete, schema: "private")),
        .postgres(PostgresJoinConfig(event: .all, schema: "public", table: "messages")),
      ],
      accessToken: nil,
      version: nil
    )

    expectNoDifference(
      payload["config"]?.objectValue?["postgres_changes"],
      [
        ["event": "UPDATE", "schema": "public", "table": "orders"],
        [
          "event": "INSERT", "schema": "public", "table": "users", "filter": "id=eq.1",
          "select": ["id", "first_name"],
        ],
        ["event": "DELETE", "schema": "private"],
        ["event": "*", "schema": "public", "table": "messages"],
      ]
    )
  }

  @Test
  func postgresChangeIdIsSentOnlyWhenSet() throws {
    let payload = try joinPayload(
      config: defaultConfig,
      bindings: [
        .postgres(PostgresJoinConfig(event: .insert, schema: "public", table: "users", id: 123)),
        .postgres(PostgresJoinConfig(event: .insert, schema: "public", table: "users", id: 0)),
      ],
      accessToken: nil,
      version: nil
    )

    let changes = payload["config"]?.objectValue?["postgres_changes"]?.arrayValue
    #expect(changes?[0].objectValue?["id"] == 123)
    #expect(changes?[1].objectValue?["id"] == nil)
  }

  @Test
  func postgresChangeEventRawValues() {
    #expect(PostgresChangeEvent.insert.rawValue == "INSERT")
    #expect(PostgresChangeEvent.update.rawValue == "UPDATE")
    #expect(PostgresChangeEvent.delete.rawValue == "DELETE")
    #expect(PostgresChangeEvent.all.rawValue == "*")
  }

  @Test
  func postgresChangeEventFromRawValue() {
    #expect(PostgresChangeEvent(rawValue: "INSERT") == .insert)
    #expect(PostgresChangeEvent(rawValue: "UPDATE") == .update)
    #expect(PostgresChangeEvent(rawValue: "DELETE") == .delete)
    #expect(PostgresChangeEvent(rawValue: "*") == .all)
    #expect(PostgresChangeEvent(rawValue: "INVALID") == nil)
  }

  @Test
  func postgresChangeEventCodable() throws {
    let events: [PostgresChangeEvent] = [.insert, .update, .delete, .all]

    let data = try JSONEncoder().encode(events)
    let decodedEvents = try JSONDecoder().decode([PostgresChangeEvent].self, from: data)

    #expect(decodedEvents == events)
  }
}
