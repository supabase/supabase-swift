//
//  RealtimeClientChannelsTests.swift
//  RealtimeTests
//
//  Created by Guilherme Souza on 29/10/26.
//

import Foundation
import Testing

@testable import Realtime

@Suite
struct RealtimeClientChannelsTests {
  let client = RealtimeClient(
    url: URL(string: "http://localhost:54321/realtime/v1")!,
    options: RealtimeClientOptions(
      disconnectOnEmptyChannelsAfter: .zero,
      handleAppLifecycle: false
    )
  )

  @Test
  func channelsListsCreatedChannels() async {
    _ = await client.channel("a")
    _ = await client.channel("b")
    _ = await client.channel("a")

    let topics = await client.channels.map(\.topic)
    #expect(topics.count == 2)
    #expect(Set(topics) == ["a", "b"])
  }

  @Test
  func channelsDropsRemovedChannels() async {
    let first = await client.channel("a")
    _ = await client.channel("b")

    await client.removeChannel(first)

    #expect(await client.channels.map(\.topic) == ["b"])
  }

  @Test
  func channelsDropsAChannelTheServerClosed() async {
    let channel = await client.channel("a")

    await channel.onMessage(
      RealtimeMessage(
        joinRef: nil, ref: nil, topic: channel.topic, event: ChannelEvent.close, payload: [:]
      )
    )

    #expect(await client.channels.isEmpty)
  }

  @Test
  func aLateCloseForAnOldChannelKeepsTheNewChannelWithTheSameTopic() async {
    let old = await client.channel("a")
    await client.removeChannel(old)
    let new = await client.channel("a")

    await old.onMessage(
      RealtimeMessage(
        joinRef: nil, ref: nil, topic: old.topic, event: ChannelEvent.close, payload: [:]
      )
    )

    #expect(await client.channels.count == 1)
    #expect(await client.channels.first === new)
  }

  @Test
  func removingAnOldChannelKeepsTheNewChannelWithTheSameTopic() async {
    let old = await client.channel("a")
    await old.onMessage(
      RealtimeMessage(
        joinRef: nil, ref: nil, topic: old.topic, event: ChannelEvent.close, payload: [:]
      )
    )
    let new = await client.channel("a")

    await client.removeChannel(old)

    #expect(await client.channels.count == 1)
    #expect(await client.channels.first === new)
  }

  @Test
  func configureAppliesTheConfiguration() async {
    let channel = await client.channel("private-room", configure: { $0.isPrivate = true })

    #expect(channel.configuration.isPrivate)
  }
}
