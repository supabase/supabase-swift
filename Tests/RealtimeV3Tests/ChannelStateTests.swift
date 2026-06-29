//
//  ChannelStateTests.swift
//  RealtimeV3
//
//  Created by Guilherme Souza on 29/06/26.
//

import Foundation
import Testing

@testable import RealtimeV3

@Suite struct ChannelStateTests {
  @Test func defaultOptions() {
    let o = ChannelOptions()
    #expect(o.isPrivate == false)
    #expect(o.broadcast.acknowledge == false)
    #expect(o.presence.enabled == false)
  }

  @Test func channelStartsUnsubscribed() async {
    let (transport, _) = InMemoryTransport.pair()
    let rt = Realtime(url: URL(string: "wss://x")!, apiKey: "k", transport: transport)
    let channel = await rt.channel("room:1")
    var it = await channel.state.makeAsyncIterator()
    let first = await it.next()
    #expect(first == .unsubscribed)
  }
}
