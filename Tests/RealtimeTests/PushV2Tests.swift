//
//  PushV2Tests.swift
//  Supabase
//
//  Created by Guilherme Souza on 29/07/25.
//

import XCTest

@testable import Realtime

final class PushV2Tests: XCTestCase {

  func testPushStatusValues() {
    XCTAssertEqual(PushStatus.ok.rawValue, "ok")
    XCTAssertEqual(PushStatus.error.rawValue, "error")
    XCTAssertEqual(PushStatus.timeout.rawValue, "timeout")
  }

  func testPushStatusFromRawValue() {
    XCTAssertEqual(PushStatus(rawValue: "ok"), .ok)
    XCTAssertEqual(PushStatus(rawValue: "error"), .error)
    XCTAssertEqual(PushStatus(rawValue: "timeout"), .timeout)
    XCTAssertNil(PushStatus(rawValue: "invalid"))
  }

  @MainActor
  func testPushV2InitializationWithNilChannel() {
    let sampleMessage = RealtimeMessageV2(
      joinRef: "ref1",
      ref: "ref2",
      topic: "test:channel",
      event: "broadcast",
      payload: ["data": "test"]
    )

    let push = PushV2(channel: nil, message: sampleMessage)

    XCTAssertEqual(push.message.topic, "test:channel")
    XCTAssertEqual(push.message.event, "broadcast")
  }

  @MainActor
  func testSendWithNilChannelReturnsError() async {
    let sampleMessage = RealtimeMessageV2(
      joinRef: "ref1",
      ref: "ref2",
      topic: "test:channel",
      event: "broadcast",
      payload: ["data": "test"]
    )

    let push = PushV2(channel: nil, message: sampleMessage)

    let status = await push.send()

    XCTAssertEqual(status, .error)
  }
}
