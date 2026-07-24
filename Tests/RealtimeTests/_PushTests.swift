//
//  _PushTests.swift
//
//
//  Created by Guilherme Souza on 03/01/24.
//

import ConcurrencyExtras
import Foundation
import TestHelpers
import Testing

@testable import Realtime
@testable import RealtimeV2

#if !os(Android) && !os(Linux) && !os(Windows)
  @Suite
  @MainActor
  struct _PushTests {
    let ws: FakeWebSocket
    let socket: RealtimeClientV2

    init() {
      let (client, server) = FakeWebSocket.fakes()
      ws = server

      socket = RealtimeClientV2(
        url: URL(string: "https://localhost:54321/v1/realtime")!,
        options: RealtimeClientOptions(
          headers: ["apiKey": "apikey"]
        ),
        wsTransport: { _, _ in client },
        http: HTTPClientMock(),
        clock: ContinuousClock()
      )
    }

    @Test
    func pushWithoutAck() async {
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
      #expect(status == .ok)
    }

    @Test
    func pushWithAck() async {
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
      #expect(status == .ok)
    }
  }
#endif
