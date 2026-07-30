//
//  RealtimeMessageV2Tests.swift
//
//
//  Created by Guilherme Souza on 26/06/24.
//

import Foundation
import Testing

@testable import Realtime
@testable import RealtimeV2

@Suite
struct RealtimeMessageV2Tests {
  @Test
  func status() {
    var message = RealtimeMessageV2(
      joinRef: nil, ref: nil, topic: "heartbeat", event: "event", payload: ["status": "ok"])
    #expect(message.status == .ok)

    message = RealtimeMessageV2(
      joinRef: nil, ref: nil, topic: "heartbeat", event: "event", payload: ["status": "timeout"])
    #expect(message.status == .timeout)

    message = RealtimeMessageV2(
      joinRef: nil, ref: nil, topic: "heartbeat", event: "event", payload: ["status": "error"])
    #expect(message.status == .error)

    message = RealtimeMessageV2(
      joinRef: nil, ref: nil, topic: "heartbeat", event: "event", payload: ["status": "invalid"])
    #expect(message.status == nil)
  }

  @Test
  func eventType() {
    let payloadWithStatusOK: JSONObject = ["status": "ok"]
    let payloadWithNoStatus: JSONObject = [:]

    let systemEventMessage = RealtimeMessageV2(
      joinRef: nil, ref: nil, topic: "topic", event: ChannelEvent.system,
      payload: payloadWithStatusOK)
    let postgresChangesEventMessage = RealtimeMessageV2(
      joinRef: nil, ref: nil, topic: "topic", event: ChannelEvent.postgresChanges,
      payload: payloadWithNoStatus)

    #expect(systemEventMessage._eventType == .system)
    #expect(postgresChangesEventMessage._eventType == .postgresChanges)

    let broadcastEventMessage = RealtimeMessageV2(
      joinRef: nil, ref: nil, topic: "topic", event: ChannelEvent.broadcast,
      payload: payloadWithNoStatus)
    #expect(broadcastEventMessage._eventType == .broadcast)

    let closeEventMessage = RealtimeMessageV2(
      joinRef: nil, ref: nil, topic: "topic", event: ChannelEvent.close,
      payload: payloadWithNoStatus)
    #expect(closeEventMessage._eventType == .close)

    let errorEventMessage = RealtimeMessageV2(
      joinRef: nil, ref: nil, topic: "topic", event: ChannelEvent.error,
      payload: payloadWithNoStatus)
    #expect(errorEventMessage._eventType == .error)

    let presenceDiffEventMessage = RealtimeMessageV2(
      joinRef: nil, ref: nil, topic: "topic", event: ChannelEvent.presenceDiff,
      payload: payloadWithNoStatus)
    #expect(presenceDiffEventMessage._eventType == .presenceDiff)

    let presenceStateEventMessage = RealtimeMessageV2(
      joinRef: nil, ref: nil, topic: "topic", event: ChannelEvent.presenceState,
      payload: payloadWithNoStatus)
    #expect(presenceStateEventMessage._eventType == .presenceState)

    let replyEventMessage = RealtimeMessageV2(
      joinRef: nil, ref: nil, topic: "topic", event: ChannelEvent.reply,
      payload: payloadWithNoStatus)
    #expect(replyEventMessage._eventType == .reply)

    let unknownEventMessage = RealtimeMessageV2(
      joinRef: nil, ref: nil, topic: "topic", event: "unknown_event", payload: payloadWithNoStatus)
    #expect(unknownEventMessage._eventType == nil)
  }

  @Test
  func messageWithNilRefs() throws {
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
    #expect(decoded.joinRef == nil)
    #expect(decoded.ref == nil)
    #expect(decoded.topic == "phoenix")
    #expect(decoded.event == "heartbeat")
  }

  @Test
  func heartbeatMessageWithNilJoinRef() throws {
    let message = RealtimeMessageV2(
      joinRef: nil,  // Heartbeats don't have joinRef
      ref: "123",
      topic: "phoenix",
      event: "heartbeat",
      payload: [:]
    )
    let encoded = try JSONEncoder().encode(message)
    let decoded = try JSONDecoder().decode(RealtimeMessageV2.self, from: encoded)
    #expect(decoded.joinRef == nil)
    #expect(decoded.ref == "123")
  }

  @Test
  func messageJSONEncodingWithNilRefs() throws {
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
    #expect(jsonString.contains("\"join_ref\":null") || !jsonString.contains("join_ref"))
    #expect(jsonString.contains("\"ref\":null") || !jsonString.contains("ref"))
  }

  @Test
  func messageWithBothRefAndJoinRef() throws {
    let message = RealtimeMessageV2(
      joinRef: "join-456",
      ref: "ref-789",
      topic: "room:lobby",
      event: "join",
      payload: ["user_id": "123"]
    )
    let encoded = try JSONEncoder().encode(message)
    let decoded = try JSONDecoder().decode(RealtimeMessageV2.self, from: encoded)
    #expect(decoded.joinRef == "join-456")
    #expect(decoded.ref == "ref-789")
    #expect(decoded.topic == "room:lobby")
  }

  @Test
  func messageWithRefButNilJoinRef() throws {
    let message = RealtimeMessageV2(
      joinRef: nil,
      ref: "ref-999",
      topic: "room:lobby",
      event: "leave",
      payload: [:]
    )
    let encoded = try JSONEncoder().encode(message)
    let decoded = try JSONDecoder().decode(RealtimeMessageV2.self, from: encoded)
    #expect(decoded.joinRef == nil)
    #expect(decoded.ref == "ref-999")
    #expect(decoded.topic == "room:lobby")
  }
}
