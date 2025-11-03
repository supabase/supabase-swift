//
//  _PushTests.swift
//
//
//  Created by Guilherme Souza on 03/01/24.
//

import ConcurrencyExtras
import TestHelpers
@preconcurrency import XCTest

@testable import Realtime

#if !os(Android) && !os(Linux) && !os(Windows)
  @MainActor
  final class _PushTests: XCTestCase {
    var ws: FakeWebSocket!
    var socket: RealtimeClientV2!

    override func setUp() async throws {
      try await super.setUp()

      let (client, server) = FakeWebSocket.fakes()
      ws = server

      socket = RealtimeClientV2(
        url: URL(string: "https://localhost:54321/v1/realtime")!,
        options: RealtimeClientOptions(
          headers: ["apiKey": "apikey"]
        ),
        wsTransport: { _, _ in client },
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

    func testPushWithAck() async {
      let channel = RealtimeChannelV2(
        topic: "realtime:users",
        config: RealtimeChannelConfig(
          broadcast: .init(acknowledgeBroadcasts: true),
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

      let task = Task {
        await push.send()
      }
      await Task.megaYield()
      push.didReceive(status: .ok)

      let status = await task.value
      XCTAssertEqual(status, .ok)
    }
  }
#endif
