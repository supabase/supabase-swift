//
//  _PushTests.swift
//
//
//  Created by Guilherme Souza on 03/01/24.
//

import ConcurrencyExtras
import TestHelpers
import XCTest

@testable import Realtime

#if !os(Android) && !os(Linux) && !os(Windows)
 @MainActor
 @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
 final class _PushTests: XCTestCase {
   var ws: FakeWebSocket!
   var socket: RealtimeClient!

   override func setUp() {
     super.setUp()

     let (client, server) = FakeWebSocket.fakes()
     ws = server

     socket = RealtimeClient(
       url: URL(string: "https://localhost:54321/v1/realtime")!,
       options: RealtimeClientOptions(
         headers: ["apiKey": "apikey"]
       ),
       wsTransport: { _, _ in client },
       session: .default
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

   func testPushWithAck() async {
     let channel = RealtimeChannel(
       topic: "realtime:users",
       config: RealtimeChannelConfig(
         broadcast: .init(acknowledgeBroadcasts: true),
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
