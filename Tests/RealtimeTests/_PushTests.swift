//
//  _PushTests.swift
//
//
//  Created by Guilherme Souza on 03/01/24.
//

@testable import Realtime
import XCTest

final class _PushTests: XCTestCase {
  let socket = Realtime(config: Realtime.Configuration(
    url: URL(string: "https://localhost:54321/v1/realtime")!,
    apiKey: "apikey",
    authTokenProvider: nil
  ))

  func testPushWithoutAck() async {
    let channel = RealtimeChannelV2(
      topic: "realtime:users",
      config: RealtimeChannelConfig(
        broadcast: .init(acknowledgeBroadcasts: false),
        presence: .init()
      ),
      socket: socket
    )
    let push = _Push(
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

  func testPushWithAck() async {
    let channel = RealtimeChannelV2(
      topic: "realtime:users",
      config: RealtimeChannelConfig(
        broadcast: .init(acknowledgeBroadcasts: true),
        presence: .init()
      ),
      socket: socket
    )
    let push = _Push(
      channel: channel,
      message: RealtimeMessageV2(
        joinRef: nil,
        ref: "1",
        topic: "realtime:users",
        event: "broadcast",
        payload: [:]
      )
    )

    let task = Task {
      await push.send()
    }
    await Task.megaYield()

    push.didReceive(status: .ok)

    let status = await task.value
    XCTAssertEqual(status, .ok)
  }
}
