//
//  RealtimeMessageV2Tests.swift
//
//
//  Created by Guilherme Souza on 26/06/24.
//

@testable import Realtime
import XCTest

final class RealtimeMessageV2Tests: XCTestCase {
  func testStatus() {
    var message = RealtimeMessageV2(joinRef: nil, ref: nil, topic: "heartbeat", event: "event", payload: ["status": "ok"])
    XCTAssertEqual(message.status, .ok)

    message = RealtimeMessageV2(joinRef: nil, ref: nil, topic: "heartbeat", event: "event", payload: ["status": "timeout"])
    XCTAssertEqual(message.status, .timeout)

    message = RealtimeMessageV2(joinRef: nil, ref: nil, topic: "heartbeat", event: "event", payload: ["status": "error"])
    XCTAssertEqual(message.status, .error)

    message = RealtimeMessageV2(joinRef: nil, ref: nil, topic: "heartbeat", event: "event", payload: ["status": "invalid"])
    XCTAssertNil(message.status)
  }

  func testEventType() {
    let payloadWithTokenExpiredMessage: JSONObject = ["message": "access token has expired"]
    let payloadWithStatusOK: JSONObject = ["status": "ok"]
    let payloadWithNoStatus: JSONObject = [:]

    let systemEventMessage = RealtimeMessageV2(joinRef: nil, ref: nil, topic: "topic", event: ChannelEvent.system, payload: payloadWithStatusOK)
    let postgresChangesEventMessage = RealtimeMessageV2(joinRef: nil, ref: nil, topic: "topic", event: ChannelEvent.postgresChanges, payload: payloadWithNoStatus)
    let tokenExpiredEventMessage = RealtimeMessageV2(joinRef: nil, ref: nil, topic: "topic", event: ChannelEvent.system, payload: payloadWithTokenExpiredMessage)

    XCTAssertEqual(systemEventMessage.eventType, .system)
    XCTAssertEqual(postgresChangesEventMessage.eventType, .postgresChanges)
    XCTAssertEqual(tokenExpiredEventMessage.eventType, .tokenExpired)

    let broadcastEventMessage = RealtimeMessageV2(joinRef: nil, ref: nil, topic: "topic", event: ChannelEvent.broadcast, payload: payloadWithNoStatus)
    XCTAssertEqual(broadcastEventMessage.eventType, .broadcast)

    let closeEventMessage = RealtimeMessageV2(joinRef: nil, ref: nil, topic: "topic", event: ChannelEvent.close, payload: payloadWithNoStatus)
    XCTAssertEqual(closeEventMessage.eventType, .close)

    let errorEventMessage = RealtimeMessageV2(joinRef: nil, ref: nil, topic: "topic", event: ChannelEvent.error, payload: payloadWithNoStatus)
    XCTAssertEqual(errorEventMessage.eventType, .error)

    let presenceDiffEventMessage = RealtimeMessageV2(joinRef: nil, ref: nil, topic: "topic", event: ChannelEvent.presenceDiff, payload: payloadWithNoStatus)
    XCTAssertEqual(presenceDiffEventMessage.eventType, .presenceDiff)

    let presenceStateEventMessage = RealtimeMessageV2(joinRef: nil, ref: nil, topic: "topic", event: ChannelEvent.presenceState, payload: payloadWithNoStatus)
    XCTAssertEqual(presenceStateEventMessage.eventType, .presenceState)

    let replyEventMessage = RealtimeMessageV2(joinRef: nil, ref: nil, topic: "topic", event: ChannelEvent.reply, payload: payloadWithNoStatus)
    XCTAssertEqual(replyEventMessage.eventType, .reply)

    let unknownEventMessage = RealtimeMessageV2(joinRef: nil, ref: nil, topic: "topic", event: "unknown_event", payload: payloadWithNoStatus)
    XCTAssertNil(unknownEventMessage.eventType)
  }
}
