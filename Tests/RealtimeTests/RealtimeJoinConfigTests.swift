//
//  RealtimeJoinConfigTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 29/07/25.
//

import XCTest

@testable import Realtime

final class RealtimeJoinConfigTests: XCTestCase {
  
  // MARK: - RealtimeJoinPayload Tests
  
  func testRealtimeJoinPayloadInit() {
    let config = RealtimeJoinConfig()
    let payload = RealtimeJoinPayload(
      config: config,
      accessToken: "token123",
      version: "1.0"
    )
    
    XCTAssertEqual(payload.config, config)
    XCTAssertEqual(payload.accessToken, "token123")
    XCTAssertEqual(payload.version, "1.0")
  }
  
  func testRealtimeJoinPayloadCodingKeys() throws {
    let config = RealtimeJoinConfig()
    let payload = RealtimeJoinPayload(
      config: config,
      accessToken: "token123",
      version: "1.0"
    )
    
    let encoder = JSONEncoder()
    let data = try encoder.encode(payload)
    
    let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    XCTAssertNotNil(jsonObject?["config"])
    XCTAssertEqual(jsonObject?["access_token"] as? String, "token123")
    XCTAssertEqual(jsonObject?["version"] as? String, "1.0")
  }
  
  func testRealtimeJoinPayloadDecoding() throws {
    let jsonData = """
    {
      "config": {
        "broadcast": {"ack": false, "self": false},
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
    
    XCTAssertEqual(payload.accessToken, "token123")
    XCTAssertEqual(payload.version, "1.0")
    XCTAssertFalse(payload.config.isPrivate)
  }
  
  // MARK: - RealtimeJoinConfig Tests
  
  func testRealtimeJoinConfigDefaults() {
    let config = RealtimeJoinConfig()
    
    XCTAssertFalse(config.broadcast.acknowledgeBroadcasts)
    XCTAssertFalse(config.broadcast.receiveOwnBroadcasts)
    XCTAssertEqual(config.presence.key, "")
    XCTAssertFalse(config.presence.enabled)
    XCTAssertTrue(config.postgresChanges.isEmpty)
    XCTAssertFalse(config.isPrivate)
  }
  
  func testRealtimeJoinConfigCustomValues() {
    var config = RealtimeJoinConfig()
    config.broadcast.acknowledgeBroadcasts = true
    config.broadcast.receiveOwnBroadcasts = true
    config.presence.key = "user123"
    config.presence.enabled = true
    config.isPrivate = true
    config.postgresChanges = [
      PostgresJoinConfig(event: .insert, schema: "public", table: "users", filter: nil, id: 1)
    ]
    
    XCTAssertTrue(config.broadcast.acknowledgeBroadcasts)
    XCTAssertTrue(config.broadcast.receiveOwnBroadcasts)
    XCTAssertEqual(config.presence.key, "user123")
    XCTAssertTrue(config.presence.enabled)
    XCTAssertTrue(config.isPrivate)
    XCTAssertEqual(config.postgresChanges.count, 1)
  }
  
  func testRealtimeJoinConfigEquality() {
    let config1 = RealtimeJoinConfig()
    var config2 = RealtimeJoinConfig()
    config2.isPrivate = false
    
    XCTAssertEqual(config1, config2)
    
    config2.isPrivate = true
    XCTAssertNotEqual(config1, config2)
  }
  
  func testRealtimeJoinConfigHashable() {
    let config1 = RealtimeJoinConfig()
    var config2 = RealtimeJoinConfig()
    config2.isPrivate = false
    
    XCTAssertEqual(config1.hashValue, config2.hashValue)
    
    config2.isPrivate = true
    XCTAssertNotEqual(config1.hashValue, config2.hashValue)
  }
  
  func testRealtimeJoinConfigCodingKeys() throws {
    var config = RealtimeJoinConfig()
    config.isPrivate = true
    config.postgresChanges = [
      PostgresJoinConfig(event: .insert, schema: "public", table: "users", filter: nil, id: 1)
    ]
    
    let encoder = JSONEncoder()
    let data = try encoder.encode(config)
    
    let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    XCTAssertNotNil(jsonObject?["broadcast"])
    XCTAssertNotNil(jsonObject?["presence"])
    XCTAssertNotNil(jsonObject?["postgres_changes"])
    XCTAssertEqual(jsonObject?["private"] as? Bool, true)
  }
  
  // MARK: - BroadcastJoinConfig Tests
  
  func testBroadcastJoinConfigDefaults() {
    let config = BroadcastJoinConfig()
    
    XCTAssertFalse(config.acknowledgeBroadcasts)
    XCTAssertFalse(config.receiveOwnBroadcasts)
  }
  
  func testBroadcastJoinConfigCustomValues() {
    let config = BroadcastJoinConfig(
      acknowledgeBroadcasts: true,
      receiveOwnBroadcasts: true
    )
    
    XCTAssertTrue(config.acknowledgeBroadcasts)
    XCTAssertTrue(config.receiveOwnBroadcasts)
  }
  
  func testBroadcastJoinConfigCodingKeys() throws {
    let config = BroadcastJoinConfig(
      acknowledgeBroadcasts: true,
      receiveOwnBroadcasts: true
    )
    
    let encoder = JSONEncoder()
    let data = try encoder.encode(config)
    
    let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    XCTAssertEqual(jsonObject?["ack"] as? Bool, true)
    XCTAssertEqual(jsonObject?["self"] as? Bool, true)
  }
  
  func testBroadcastJoinConfigDecoding() throws {
    let jsonData = """
    {
      "ack": true,
      "self": false
    }
    """.data(using: .utf8)!
    
    let decoder = JSONDecoder()
    let config = try decoder.decode(BroadcastJoinConfig.self, from: jsonData)
    
    XCTAssertTrue(config.acknowledgeBroadcasts)
    XCTAssertFalse(config.receiveOwnBroadcasts)
  }
  
  // MARK: - PresenceJoinConfig Tests
  
  func testPresenceJoinConfigDefaults() {
    let config = PresenceJoinConfig()
    
    XCTAssertEqual(config.key, "")
    XCTAssertFalse(config.enabled)
  }
  
  func testPresenceJoinConfigCustomValues() {
    var config = PresenceJoinConfig()
    config.key = "user123"
    config.enabled = true
    
    XCTAssertEqual(config.key, "user123")
    XCTAssertTrue(config.enabled)
  }
  
  func testPresenceJoinConfigCodable() throws {
    var config = PresenceJoinConfig()
    config.key = "user123"
    config.enabled = true
    
    let encoder = JSONEncoder()
    let data = try encoder.encode(config)
    
    let decoder = JSONDecoder()
    let decodedConfig = try decoder.decode(PresenceJoinConfig.self, from: data)
    
    XCTAssertEqual(decodedConfig.key, "user123")
    XCTAssertTrue(decodedConfig.enabled)
  }
  
  // MARK: - PostgresChangeEvent Tests
  
  func testPostgresChangeEventRawValues() {
    XCTAssertEqual(PostgresChangeEvent.insert.rawValue, "INSERT")
    XCTAssertEqual(PostgresChangeEvent.update.rawValue, "UPDATE")
    XCTAssertEqual(PostgresChangeEvent.delete.rawValue, "DELETE")
    XCTAssertEqual(PostgresChangeEvent.all.rawValue, "*")
  }
  
  func testPostgresChangeEventFromRawValue() {
    XCTAssertEqual(PostgresChangeEvent(rawValue: "INSERT"), .insert)
    XCTAssertEqual(PostgresChangeEvent(rawValue: "UPDATE"), .update)
    XCTAssertEqual(PostgresChangeEvent(rawValue: "DELETE"), .delete)
    XCTAssertEqual(PostgresChangeEvent(rawValue: "*"), .all)
    XCTAssertNil(PostgresChangeEvent(rawValue: "INVALID"))
  }
  
  func testPostgresChangeEventCodable() throws {
    let events: [PostgresChangeEvent] = [.insert, .update, .delete, .all]
    
    let encoder = JSONEncoder()
    let data = try encoder.encode(events)
    
    let decoder = JSONDecoder()
    let decodedEvents = try decoder.decode([PostgresChangeEvent].self, from: data)
    
    XCTAssertEqual(decodedEvents, events)
  }
  
  // MARK: - PostgresJoinConfig Additional Tests
  
  func testPostgresJoinConfigDefaults() {
    let config = PostgresJoinConfig(event: .insert, schema: "public", table: "users", filter: nil, id: 0)
    
    XCTAssertEqual(config.event, .insert)
    XCTAssertEqual(config.schema, "public")
    XCTAssertEqual(config.table, "users")
    XCTAssertNil(config.filter)
    XCTAssertEqual(config.id, 0)
  }
  
  func testPostgresJoinConfigCustomEncoding() throws {
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
    XCTAssertEqual(jsonObject?["event"] as? String, "INSERT")
    XCTAssertEqual(jsonObject?["schema"] as? String, "public")
    XCTAssertEqual(jsonObject?["table"] as? String, "users")
    XCTAssertEqual(jsonObject?["filter"] as? String, "id=1")
    XCTAssertEqual(jsonObject?["id"] as? Int, 123)
  }
  
  func testPostgresJoinConfigEncodingWithZeroId() throws {
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
    XCTAssertNil(jsonObject?["id"]) // Should not encode id when it's 0
  }
  
  func testPostgresJoinConfigEncodingWithNilValues() throws {
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
    XCTAssertNil(jsonObject?["table"]) // Should not encode nil table
    XCTAssertNil(jsonObject?["filter"]) // Should not encode nil filter
  }
}