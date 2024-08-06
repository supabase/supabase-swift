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
  var socket: RealtimeClient!

  override func invokeTest() {
    withMainSerialExecutor {
      super.invokeTest()
    }
  }

  override func setUp() {
    super.setUp()

    ws = MockWebSocketClient()
    socket = RealtimeClient(
      url: URL(string: "https://localhost:54321/v1/realtime")!,
      options: RealtimeClientOptions(
        headers: ["apiKey": "apikey"]
      ),
      ws: ws,
      http: HTTPClientMock()
    )
  }

  func testPushWithoutAck() async {
    let channel = RealtimeChannel(
      topic: "realtime:users",
      config: RealtimeChannelConfig(
        broadcast: .init(acknowledgeBroadcasts: false),
        presence: .init(),
        isPrivate: false
      ),
      socket: socket,
      logger: nil
    )
    let push = Push(
      channel: channel,
      message: RealtimeMessage(
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
//    let channel = RealtimeChannel(
//      topic: "realtime:users",
//      config: RealtimeChannelConfig(
//        broadcast: .init(acknowledgeBroadcasts: true),
//        presence: .init()
//      ),
//      socket: socket,
//      logger: nil
//    )
//    let push = Push(
//      channel: channel,
//      message: RealtimeMessage(
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
