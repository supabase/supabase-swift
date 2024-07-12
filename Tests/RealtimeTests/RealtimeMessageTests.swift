//
//  RealtimeMessageTests.swift
//
//
//  Created by Guilherme Souza on 26/06/24.
//

@testable import Realtime
import XCTest

final class RealtimeMessageTests: XCTestCase {
  func testStatus() {
    var message = RealtimeMessage(joinRef: nil, ref: nil, topic: "heartbeat", event: "event", payload: ["status": "ok"])
    XCTAssertEqual(message.status, .ok)

    message = RealtimeMessage(joinRef: nil, ref: nil, topic: "heartbeat", event: "event", payload: ["status": "timeout"])
    XCTAssertEqual(message.status, .timeout)

    message = RealtimeMessage(joinRef: nil, ref: nil, topic: "heartbeat", event: "event", payload: ["status": "error"])
    XCTAssertEqual(message.status, .error)

    message = RealtimeMessage(joinRef: nil, ref: nil, topic: "heartbeat", event: "event", payload: ["status": "invalid"])
    XCTAssertNil(message.status)
  }

  func testEventType() {
    let payloadWithTokenExpiredMessage: JSONObject = ["message": "access token has expired"]
    let payloadWithStatusOK: JSONObject = ["status": "ok"]
    let payloadWithNoStatus: JSONObject = [:]

    let systemEventMessage = RealtimeMessage(joinRef: nil, ref: nil, topic: "topic", event: ChannelEvent.system, payload: payloadWithStatusOK)
    let postgresChangesEventMessage = RealtimeMessage(joinRef: nil, ref: nil, topic: "topic", event: ChannelEvent.postgresChanges, payload: payloadWithNoStatus)
    let tokenExpiredEventMessage = RealtimeMessage(joinRef: nil, ref: nil, topic: "topic", event: ChannelEvent.system, payload: payloadWithTokenExpiredMessage)

    XCTAssertEqual(systemEventMessage.eventType, .system)
    XCTAssertEqual(postgresChangesEventMessage.eventType, .postgresChanges)
    XCTAssertEqual(tokenExpiredEventMessage.eventType, .tokenExpired)

    let broadcastEventMessage = RealtimeMessage(joinRef: nil, ref: nil, topic: "topic", event: ChannelEvent.broadcast, payload: payloadWithNoStatus)
    XCTAssertEqual(broadcastEventMessage.eventType, .broadcast)

    let closeEventMessage = RealtimeMessage(joinRef: nil, ref: nil, topic: "topic", event: ChannelEvent.close, payload: payloadWithNoStatus)
    XCTAssertEqual(closeEventMessage.eventType, .close)

    let errorEventMessage = RealtimeMessage(joinRef: nil, ref: nil, topic: "topic", event: ChannelEvent.error, payload: payloadWithNoStatus)
    XCTAssertEqual(errorEventMessage.eventType, .error)

    let presenceDiffEventMessage = RealtimeMessage(joinRef: nil, ref: nil, topic: "topic", event: ChannelEvent.presenceDiff, payload: payloadWithNoStatus)
    XCTAssertEqual(presenceDiffEventMessage.eventType, .presenceDiff)

    let presenceStateEventMessage = RealtimeMessage(joinRef: nil, ref: nil, topic: "topic", event: ChannelEvent.presenceState, payload: payloadWithNoStatus)
    XCTAssertEqual(presenceStateEventMessage.eventType, .presenceState)

    let replyEventMessage = RealtimeMessage(joinRef: nil, ref: nil, topic: "topic", event: ChannelEvent.reply, payload: payloadWithNoStatus)
    XCTAssertEqual(replyEventMessage.eventType, .reply)

    let unknownEventMessage = RealtimeMessage(joinRef: nil, ref: nil, topic: "topic", event: "unknown_event", payload: payloadWithNoStatus)
    XCTAssertNil(unknownEventMessage.eventType)
  }
}
