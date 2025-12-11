//
//  RealtimeMessageV2Tests.swift
//
//
//  Created by Guilherme Souza on 26/06/24.
//

import XCTest

@testable import Realtime

final class RealtimeMessageV2Tests: XCTestCase {
  func testStatus() {
    var message = RealtimeMessageV2(
      joinRef: nil, ref: nil, topic: "heartbeat", event: "event", payload: ["status": "ok"])
    XCTAssertEqual(message.status, .ok)

    message = RealtimeMessageV2(
      joinRef: nil, ref: nil, topic: "heartbeat", event: "event", payload: ["status": "timeout"])
    XCTAssertEqual(message.status, .timeout)

    message = RealtimeMessageV2(
      joinRef: nil, ref: nil, topic: "heartbeat", event: "event", payload: ["status": "error"])
    XCTAssertEqual(message.status, .error)

    message = RealtimeMessageV2(
      joinRef: nil, ref: nil, topic: "heartbeat", event: "event", payload: ["status": "invalid"])
    XCTAssertNil(message.status)
  }

  func testEventType() {
    let payloadWithStatusOK: JSONObject = ["status": "ok"]
    let payloadWithNoStatus: JSONObject = [:]

    let systemEventMessage = RealtimeMessageV2(
      joinRef: nil, ref: nil, topic: "topic", event: ChannelEvent.system,
      payload: payloadWithStatusOK)
    let postgresChangesEventMessage = RealtimeMessageV2(
      joinRef: nil, ref: nil, topic: "topic", event: ChannelEvent.postgresChanges,
      payload: payloadWithNoStatus)

    XCTAssertEqual(systemEventMessage._eventType, .system)
    XCTAssertEqual(postgresChangesEventMessage._eventType, .postgresChanges)

    let broadcastEventMessage = RealtimeMessageV2(
      joinRef: nil, ref: nil, topic: "topic", event: ChannelEvent.broadcast,
      payload: payloadWithNoStatus)
    XCTAssertEqual(broadcastEventMessage._eventType, .broadcast)

    let closeEventMessage = RealtimeMessageV2(
      joinRef: nil, ref: nil, topic: "topic", event: ChannelEvent.close,
      payload: payloadWithNoStatus)
    XCTAssertEqual(closeEventMessage._eventType, .close)

    let errorEventMessage = RealtimeMessageV2(
      joinRef: nil, ref: nil, topic: "topic", event: ChannelEvent.error,
      payload: payloadWithNoStatus)
    XCTAssertEqual(errorEventMessage._eventType, .error)

    let presenceDiffEventMessage = RealtimeMessageV2(
      joinRef: nil, ref: nil, topic: "topic", event: ChannelEvent.presenceDiff,
      payload: payloadWithNoStatus)
    XCTAssertEqual(presenceDiffEventMessage._eventType, .presenceDiff)

    let presenceStateEventMessage = RealtimeMessageV2(
      joinRef: nil, ref: nil, topic: "topic", event: ChannelEvent.presenceState,
      payload: payloadWithNoStatus)
    XCTAssertEqual(presenceStateEventMessage._eventType, .presenceState)

    let replyEventMessage = RealtimeMessageV2(
      joinRef: nil, ref: nil, topic: "topic", event: ChannelEvent.reply,
      payload: payloadWithNoStatus)
    XCTAssertEqual(replyEventMessage._eventType, .reply)

    let unknownEventMessage = RealtimeMessageV2(
      joinRef: nil, ref: nil, topic: "topic", event: "unknown_event", payload: payloadWithNoStatus)
    XCTAssertNil(unknownEventMessage._eventType)
  }

  func testMessageWithNilRefs() throws {
    let message = RealtimeMessageV2(
      joinRef: nil,
      ref: nil,
      topic: "phoenix",
      event: "heartbeat",
      payload: [:]
    )
    // Verify JSON encoding works
    let encoded = try JSONEncoder().encode(message)
    let decoded = try JSONDecoder().decode(RealtimeMessageV2.self, from: encoded)
    XCTAssertNil(decoded.joinRef)
    XCTAssertNil(decoded.ref)
    XCTAssertEqual(decoded.topic, "phoenix")
    XCTAssertEqual(decoded.event, "heartbeat")
  }

  func testHeartbeatMessageWithNilJoinRef() throws {
    let message = RealtimeMessageV2(
      joinRef: nil,  // Heartbeats don't have joinRef
      ref: "123",
      topic: "phoenix",
      event: "heartbeat",
      payload: [:]
    )
    let encoded = try JSONEncoder().encode(message)
    let decoded = try JSONDecoder().decode(RealtimeMessageV2.self, from: encoded)
    XCTAssertNil(decoded.joinRef)
    XCTAssertEqual(decoded.ref, "123")
  }

  func testMessageJSONEncodingWithNilRefs() throws {
    let message = RealtimeMessageV2(
      joinRef: nil,
      ref: nil,
      topic: "test",
      event: "custom",
      payload: ["key": "value"]
    )
    let encoded = try JSONEncoder().encode(message)
    let jsonString = String(data: encoded, encoding: .utf8)!
    // Verify nil values are encoded as null in JSON
    XCTAssertTrue(jsonString.contains("\"join_ref\":null") || !jsonString.contains("join_ref"))
    XCTAssertTrue(jsonString.contains("\"ref\":null") || !jsonString.contains("ref"))
  }

  func testMessageWithBothRefAndJoinRef() throws {
    let message = RealtimeMessageV2(
      joinRef: "join-456",
      ref: "ref-789",
      topic: "room:lobby",
      event: "join",
      payload: ["user_id": "123"]
    )
    let encoded = try JSONEncoder().encode(message)
    let decoded = try JSONDecoder().decode(RealtimeMessageV2.self, from: encoded)
    XCTAssertEqual(decoded.joinRef, "join-456")
    XCTAssertEqual(decoded.ref, "ref-789")
    XCTAssertEqual(decoded.topic, "room:lobby")
  }

  func testMessageWithRefButNilJoinRef() throws {
    let message = RealtimeMessageV2(
      joinRef: nil,
      ref: "ref-999",
      topic: "room:lobby",
      event: "leave",
      payload: [:]
    )
    let encoded = try JSONEncoder().encode(message)
    let decoded = try JSONDecoder().decode(RealtimeMessageV2.self, from: encoded)
    XCTAssertNil(decoded.joinRef)
    XCTAssertEqual(decoded.ref, "ref-999")
    XCTAssertEqual(decoded.topic, "room:lobby")
  }
}
