//
//  _PushTests.swift
//
//
//  Created by Guilherme Souza on 03/01/24.
//

import ConcurrencyExtras
import Helpers
import TestHelpers
import XCTest

@testable import Realtime

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
final class _PushTests: XCTestCase {
  var ws: FakeWebSocket!
  var socket: RealtimeClientV2!

  override func invokeTest() {
    withMainSerialExecutor {
      super.invokeTest()
    }
  }

  override func setUp() {
    super.setUp()

    let (client, server) = FakeWebSocket.fakes()
    ws = server

    socket = RealtimeClientV2(
      url: URL(string: "https://localhost:54321/v1/realtime")!,
      options: RealtimeClientOptions(
        headers: ["apiKey": "apikey"]
      ),
      wsTransport: { client },
      http: HTTPClientMock()
    )
  }

  func testPushWithoutAck() async {
    let channel = RealtimeChannelV2(
      topic: "realtime:users",
      config: RealtimeChannelConfig(
        broadcast: .init(acknowledgeBroadcasts: false),
        presence: .init(),
        isPrivate: false
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
  //        presence: .init(),
  //        isPrivate: false
  //      ),
  //      socket: Socket(client: socket),
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
  //    await Task.yield()
  //    await push.didReceive(status: .ok)
  //
  //    let status = await task.value
  //    XCTAssertEqual(status, .ok)
  //  }
}
