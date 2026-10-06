//
//  RealtimeMessageV2Tests.swift
//
//
//  Created by Guilherme Souza on 26/06/24.
//

import Foundation
import Testing

@testable import Realtime

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
    #expect(message.status?.rawValue == "invalid")
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

    #expect(systemEventMessage.eventType == .system)
    #expect(postgresChangesEventMessage.eventType == .postgresChanges)

    let broadcastEventMessage = RealtimeMessageV2(
      joinRef: nil, ref: nil, topic: "topic", event: ChannelEvent.broadcast,
      payload: payloadWithNoStatus)
    #expect(broadcastEventMessage.eventType == .broadcast)

    let closeEventMessage = RealtimeMessageV2(
      joinRef: nil, ref: nil, topic: "topic", event: ChannelEvent.close,
      payload: payloadWithNoStatus)
    #expect(closeEventMessage.eventType == .close)

    let errorEventMessage = RealtimeMessageV2(
      joinRef: nil, ref: nil, topic: "topic", event: ChannelEvent.error,
      payload: payloadWithNoStatus)
    #expect(errorEventMessage.eventType == .error)

    let presenceDiffEventMessage = RealtimeMessageV2(
      joinRef: nil, ref: nil, topic: "topic", event: ChannelEvent.presenceDiff,
      payload: payloadWithNoStatus)
    #expect(presenceDiffEventMessage.eventType == .presenceDiff)

    let presenceStateEventMessage = RealtimeMessageV2(
      joinRef: nil, ref: nil, topic: "topic", event: ChannelEvent.presenceState,
      payload: payloadWithNoStatus)
    #expect(presenceStateEventMessage.eventType == .presenceState)

    let replyEventMessage = RealtimeMessageV2(
      joinRef: nil, ref: nil, topic: "topic", event: ChannelEvent.reply,
      payload: payloadWithNoStatus)
    #expect(replyEventMessage.eventType == .reply)

    let unknownEventMessage = RealtimeMessageV2(
      joinRef: nil, ref: nil, topic: "topic", event: "unknown_event", payload: payloadWithNoStatus)
    #expect(unknownEventMessage.eventType.rawValue == "unknown_event")
  }
}
