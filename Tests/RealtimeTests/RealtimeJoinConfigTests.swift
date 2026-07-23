//
//  RealtimeJoinConfigTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 29/07/25.
//

import Foundation
import Testing

@testable import Realtime
@testable import RealtimeV2

@Suite
struct RealtimeJoinConfigTests {

  // MARK: - RealtimeJoinPayload Tests

  @Test
  func realtimeJoinPayloadInit() {
    let config = RealtimeJoinConfig()
    let payload = RealtimeJoinPayload(
      config: config,
      accessToken: "token123",
      version: "1.0"
    )

    #expect(payload.config == config)
    #expect(payload.accessToken == "token123")
    #expect(payload.version == "1.0")
  }

  @Test
  func realtimeJoinPayloadCodingKeys() throws {
    let config = RealtimeJoinConfig()
    let payload = RealtimeJoinPayload(
      config: config,
      accessToken: "token123",
      version: "1.0"
    )

    let encoder = JSONEncoder()
    let data = try encoder.encode(payload)

    let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    #expect(jsonObject?["config"] != nil)
    #expect(jsonObject?["access_token"] as? String == "token123")
    #expect(jsonObject?["version"] as? String == "1.0")
  }

  @Test
  func realtimeJoinPayloadDecoding() throws {
    let jsonData = """
      {
        "config": {
          "broadcast": {"ack": false, "self": false, "replication_ready": false},
          "presence": {"key": "", "enabled": false},
          "postgres_changes": [],
          "private": false
        },
        "access_token": "token123",
        "version": "1.0"
      }
      """.data(using: .utf8)!

    let decoder = JSONDecoder()
    let payload = try decoder.decode(RealtimeJoinPayload.self, from: jsonData)

    #expect(payload.accessToken == "token123")
    #expect(payload.version == "1.0")
    #expect(!payload.config.isPrivate)
  }

  // MARK: - RealtimeJoinConfig Tests

  @Test
  func realtimeJoinConfigDefaults() {
    let config = RealtimeJoinConfig()

    #expect(!config.broadcast.acknowledgeBroadcasts)
    #expect(!config.broadcast.receiveOwnBroadcasts)
    #expect(config.presence.key == "")
    #expect(!config.presence.enabled)
    #expect(config.postgresChanges.isEmpty)
    #expect(!config.isPrivate)
  }

  @Test
  func realtimeJoinConfigCustomValues() {
    var config = RealtimeJoinConfig()
    config.broadcast.acknowledgeBroadcasts = true
    config.broadcast.receiveOwnBroadcasts = true
    config.presence.key = "user123"
    config.presence.enabled = true
    config.isPrivate = true
    config.postgresChanges = [
      PostgresJoinConfig(event: .insert, schema: "public", table: "users", filter: nil, id: 1)
    ]

    #expect(config.broadcast.acknowledgeBroadcasts)
    #expect(config.broadcast.receiveOwnBroadcasts)
    #expect(config.presence.key == "user123")
    #expect(config.presence.enabled)
    #expect(config.isPrivate)
    #expect(config.postgresChanges.count == 1)
  }

  @Test
  func realtimeJoinConfigEquality() {
    let config1 = RealtimeJoinConfig()
    var config2 = RealtimeJoinConfig()
    config2.isPrivate = false

    #expect(config1 == config2)

    config2.isPrivate = true
    #expect(config1 != config2)
  }

  @Test
  func realtimeJoinConfigHashable() {
    let config1 = RealtimeJoinConfig()
    var config2 = RealtimeJoinConfig()
    config2.isPrivate = false

    #expect(config1.hashValue == config2.hashValue)

    config2.isPrivate = true
    #expect(config1.hashValue != config2.hashValue)
  }

  @Test
  func realtimeJoinConfigCodingKeys() throws {
    var config = RealtimeJoinConfig()
    config.isPrivate = true
    config.postgresChanges = [
      PostgresJoinConfig(event: .insert, schema: "public", table: "users", filter: nil, id: 1)
    ]

    let encoder = JSONEncoder()
    let data = try encoder.encode(config)

    let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    #expect(jsonObject?["broadcast"] != nil)
    #expect(jsonObject?["presence"] != nil)
    #expect(jsonObject?["postgres_changes"] != nil)
    #expect(jsonObject?["private"] as? Bool == true)
  }

  // MARK: - BroadcastJoinConfig Tests

  @Test
  func broadcastJoinConfigDefaults() {
    let config = BroadcastJoinConfig()

    #expect(!config.acknowledgeBroadcasts)
    #expect(!config.receiveOwnBroadcasts)
  }

  @Test
  func broadcastJoinConfigCustomValues() {
    let config = BroadcastJoinConfig(
      acknowledgeBroadcasts: true,
      receiveOwnBroadcasts: true
    )

    #expect(config.acknowledgeBroadcasts)
    #expect(config.receiveOwnBroadcasts)
  }

  @Test
  func broadcastJoinConfigCodingKeys() throws {
    let config = BroadcastJoinConfig(
      acknowledgeBroadcasts: true,
      receiveOwnBroadcasts: true
    )

    let encoder = JSONEncoder()
    let data = try encoder.encode(config)

    let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    #expect(jsonObject?["ack"] as? Bool == true)
    #expect(jsonObject?["self"] as? Bool == true)
  }

  @Test
  func broadcastJoinConfigDecoding() throws {
    let jsonData = """
      {
        "ack": true,
        "self": false,
        "replication_ready": false
      }
      """.data(using: .utf8)!

    let decoder = JSONDecoder()
    let config = try decoder.decode(BroadcastJoinConfig.self, from: jsonData)

    #expect(config.acknowledgeBroadcasts)
    #expect(!config.receiveOwnBroadcasts)
  }

  @Test
  func broadcastJoinConfigReplicationReadyDefaultsFalse() {
    let config = BroadcastJoinConfig()

    #expect(!config.replicationReady)
  }

  @Test
  func broadcastJoinConfigEncodesReplicationReadyWhenFalse() throws {
    let config = BroadcastJoinConfig()

    let data = try JSONEncoder().encode(config)
    let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any]

    #expect(jsonObject?["replication_ready"] as? Bool == false)
  }

  @Test
  func broadcastJoinConfigEncodesReplicationReadyWhenTrue() throws {
    let config = BroadcastJoinConfig(replicationReady: true)

    let data = try JSONEncoder().encode(config)
    let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any]

    #expect(jsonObject?["replication_ready"] as? Bool == true)
  }

  @Test
  func broadcastJoinConfigDecodesReplicationReady() throws {
    let jsonData = """
      {
        "ack": false,
        "self": false,
        "replication_ready": true
      }
      """.data(using: .utf8)!

    let config = try JSONDecoder().decode(BroadcastJoinConfig.self, from: jsonData)

    #expect(config.replicationReady)
  }

  // MARK: - PresenceJoinConfig Tests

  @Test
  func presenceJoinConfigDefaults() {
    let config = PresenceJoinConfig()

    #expect(config.key == "")
    #expect(!config.enabled)
  }

  @Test
  func presenceJoinConfigCustomValues() {
    var config = PresenceJoinConfig()
    config.key = "user123"
    config.enabled = true

    #expect(config.key == "user123")
    #expect(config.enabled)
  }

  @Test
  func presenceJoinConfigCodable() throws {
    var config = PresenceJoinConfig()
    config.key = "user123"
    config.enabled = true

    let encoder = JSONEncoder()
    let data = try encoder.encode(config)

    let decoder = JSONDecoder()
    let decodedConfig = try decoder.decode(PresenceJoinConfig.self, from: data)

    #expect(decodedConfig.key == "user123")
    #expect(decodedConfig.enabled)
  }

  // MARK: - PostgresChangeEvent Tests

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

    let encoder = JSONEncoder()
    let data = try encoder.encode(events)

    let decoder = JSONDecoder()
    let decodedEvents = try decoder.decode([PostgresChangeEvent].self, from: data)

    #expect(decodedEvents == events)
  }

  // MARK: - PostgresJoinConfig Additional Tests

  @Test
  func postgresJoinConfigDefaults() {
    let config = PostgresJoinConfig(
      event: .insert, schema: "public", table: "users", filter: nil, id: 0)

    #expect(config.event == .insert)
    #expect(config.schema == "public")
    #expect(config.table == "users")
    #expect(config.filter == nil)
    #expect(config.id == 0)
  }

  @Test
  func postgresJoinConfigCustomEncoding() throws {
    let config = PostgresJoinConfig(
      event: .insert,
      schema: "public",
      table: "users",
      filter: "id=1",
      id: 123
    )

    let encoder = JSONEncoder()
    let data = try encoder.encode(config)

    let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    #expect(jsonObject?["event"] as? String == "INSERT")
    #expect(jsonObject?["schema"] as? String == "public")
    #expect(jsonObject?["table"] as? String == "users")
    #expect(jsonObject?["filter"] as? String == "id=1")
    #expect(jsonObject?["id"] as? Int == 123)
  }

  @Test
  func postgresJoinConfigEncodingWithZeroId() throws {
    let config = PostgresJoinConfig(
      event: .insert,
      schema: "public",
      table: "users",
      filter: nil,
      id: 0
    )

    let encoder = JSONEncoder()
    let data = try encoder.encode(config)

    let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    #expect(jsonObject?["id"] == nil)  // Should not encode id when it's 0
  }

  @Test
  func postgresJoinConfigEncodingWithNilValues() throws {
    let config = PostgresJoinConfig(
      event: .insert,
      schema: "public",
      table: nil,
      filter: nil,
      id: 0
    )

    let encoder = JSONEncoder()
    let data = try encoder.encode(config)

    let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    #expect(jsonObject?["table"] == nil)  // Should not encode nil table
    #expect(jsonObject?["filter"] == nil)  // Should not encode nil filter
  }
}
