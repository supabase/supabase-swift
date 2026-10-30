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
    _ = client.channel("a")
    _ = client.channel("b")
    _ = client.channel("a")

    let topics = client.channels.map(\.topic)
    #expect(topics.count == 2)
    #expect(Set(topics) == ["a", "b"])
  }

  @Test
  func channelsDropsRemovedChannels() async {
    let first = client.channel("a")
    _ = client.channel("b")

    await client.removeChannel(first)

    #expect(client.channels.map(\.topic) == ["b"])
  }

  @Test
  func channelsDropsAChannelTheServerClosed() async {
    let channel = client.channel("a")

    await client.installSubscribedRecord("a")
    await client.apply(.frame(Self.close(channel)))

    #expect(client.channels.isEmpty)
  }

  @Test
  func aLateCloseForAnOldChannelKeepsTheNewChannelWithTheSameTopic() async {
    let old = client.channel("a")
    await client.removeChannel(old)
    let new = client.channel("a")

    await client.apply(.frame(Self.close(old)))

    #expect(client.channels.count == 1)
    #expect(client.channels.first === new)
  }

  @Test
  func removingAnOldChannelKeepsTheNewChannelWithTheSameTopic() async {
    let old = client.channel("a")
    await client.installSubscribedRecord("a")
    await client.apply(.frame(Self.close(old)))
    let new = client.channel("a")

    await client.removeChannel(old)

    #expect(client.channels.count == 1)
    #expect(client.channels.first === new)
  }

  @Test
  func configureAppliesTheConfiguration() async {
    let channel = client.channel("private-room", configure: { $0.isPrivate = true })

    #expect(channel.configuration.isPrivate)
  }

  /// A server `phx_close` for `channel`, without a `join_ref`.
  private static func close(_ channel: RealtimeChannel) -> RealtimeMessage {
    RealtimeMessage(
      joinRef: nil, ref: nil, topic: channel.wireTopic, event: ChannelEvent.close, payload: [:])
  }
}
