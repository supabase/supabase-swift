//
//  _PushTests.swift
//
//
//  Created by Guilherme Souza on 03/01/24.
//

import ConcurrencyExtras
@testable import Realtime
import TestHelpers
import XCTest

final class _PushTests: XCTestCase {
  var ws: MockWebSocketClient!
  var socket: RealtimeClientV2!

  override func invokeTest() {
    withMainSerialExecutor {
      super.invokeTest()
    }
  }

  override func setUp() {
    super.setUp()

    ws = MockWebSocketClient()
    socket = RealtimeClientV2(
      config: RealtimeClientV2.Configuration(
        url: URL(string: "https://localhost:54321/v1/realtime")!,
        apiKey: "apikey"
      ),
      ws: ws
    )
  }

  func testPushWithoutAck() async {
    let channel = RealtimeChannelV2(
      topic: "realtime:users",
      config: RealtimeChannelConfig(
        broadcast: .init(acknowledgeBroadcasts: false),
        presence: .init()
      ),
      socket: socket,
      logger: nil
    )
    let push = PushV2(
      channel: channel,
      message: RealtimeMessageV2(
        joinRef: nil,
        ref: "1",
        topic: "realtime:users",
        event: "broadcast",
        payload: [:]
      )
    )

    let status = await push.send()
    XCTAssertEqual(status, .ok)
  }

  // FIXME: Flaky test, it fails some time due the task scheduling, even tho we're using withMainSerialExecutor.
//  func testPushWithAck() async {
//    let channel = RealtimeChannelV2(
//      topic: "realtime:users",
//      config: RealtimeChannelConfig(
//        broadcast: .init(acknowledgeBroadcasts: true),
//        presence: .init()
//      ),
//      socket: socket,
//      logger: nil
//    )
//    let push = PushV2(
//      channel: channel,
//      message: RealtimeMessageV2(
//        joinRef: nil,
//        ref: "1",
//        topic: "realtime:users",
//        event: "broadcast",
//        payload: [:]
//      )
//    )
//
//    let task = Task {
//      await push.send()
//    }
//    await Task.megaYield()
//    await push.didReceive(status: .ok)
//
//    let status = await task.value
//    XCTAssertEqual(status, .ok)
//  }
}
