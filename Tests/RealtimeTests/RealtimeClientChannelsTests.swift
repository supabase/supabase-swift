//
//  RealtimeClientChannelsTests.swift
//  RealtimeTests
//
//  Created by Guilherme Souza on 29/10/26.
//

import Foundation
import Helpers
import TestHelpers
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

  /// The core must not ask for presence in the next join once the last presence stream ended.
  @Test
  func endingTheLastPresenceStreamTurnsPresenceOffForTheNextJoin() async {
    let channel = await client.channel("a")
    let presence = await channel.presenceChanges()
    await client.installSubscribedRecord("a")
    await client.turnPresenceOn(in: channel)

    let reader = Task { for await _ in presence {} }
    reader.cancel()
    await reader.value

    let client = client
    #expect(await waitUntil(timeout: 5) { await client.presenceIsOn(in: channel) == false })
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

    await client.installSubscribedRecord("a")
    await client.apply(.frame(Self.close(channel)))

    #expect(await client.channels.isEmpty)
  }

  @Test
  func aLateCloseForAnOldChannelKeepsTheNewChannelWithTheSameTopic() async {
    let old = await client.channel("a")
    await client.removeChannel(old)
    let new = await client.channel("a")

    await client.apply(.frame(Self.close(old)))

    #expect(await client.channels.count == 1)
    #expect(await client.channels.first === new)
  }

  @Test
  func removingAnOldChannelKeepsTheNewChannelWithTheSameTopic() async {
    let old = await client.channel("a")
    await client.installSubscribedRecord("a")
    await client.apply(.frame(Self.close(old)))
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

  @Test
  func statusChangesReplaysCurrentStatus() async {
    var statuses = await client.statusChanges().makeAsyncIterator()

    let first = await statuses.next()
    guard case .disconnected(nil)? = first else {
      Issue.record("Expected .disconnected(nil), got \(String(describing: first))")
      return
    }
    guard case .disconnected(nil) = await client.status else {
      Issue.record("Expected .disconnected(nil), got \(await client.status)")
      return
    }
  }

  @Test
  func heartbeatsReplayLatestOnly() async {
    let early = await client.heartbeats()
    #expect(await client.latestHeartbeat == nil)

    await client.publishHeartbeat(.sent)

    var earlyIterator = early.makeAsyncIterator()
    #expect(await earlyIterator.next() == .sent)

    var lateIterator = await client.heartbeats().makeAsyncIterator()
    #expect(await lateIterator.next() == .sent)
  }

  @Test
  func creatingChannelDoesNotCancelIdleDisconnect() async throws {
    let harness = IdleDisconnectHarness()
    let client = harness.client
    try await client.connect()

    await client.removeChannel(client.channel("room"))
    #expect(await client.idleDisconnectTimer != nil)

    _ = await client.channel("x")
    #expect(await client.idleDisconnectTimer != nil)

    await harness.clock.advance(by: .seconds(5))

    for await status in await client.statusChanges() {
      if case .disconnected(nil) = status { break }
    }
  }

  @Test
  func subscribeCancelsIdleDisconnect() async throws {
    let harness = IdleDisconnectHarness()
    let client = harness.client
    try await client.connect()

    await client.removeChannel(client.channel("room"))
    #expect(await client.idleDisconnectTimer != nil)

    let channel = await client.channel("x")
    try await channel.subscribe()
    #expect(await client.idleDisconnectTimer == nil)

    await harness.clock.advance(by: .seconds(5))

    #expect(await client.status.isConnected)
    await client.disconnect()
  }

  /// A server `phx_close` for `channel`, without a `join_ref`.
  private static func close(_ channel: RealtimeChannel) -> RealtimeMessage {
    RealtimeMessage(
      joinRef: nil, ref: nil, topic: channel.wireTopic, event: ChannelEvent.close, payload: [:])
  }
}

/// A connected-on-demand client with a 5 s idle disconnect, whose server confirms every join.
private final class IdleDisconnectHarness: Sendable {
  let clock = SignalingTestClock()
  let client: RealtimeClient
  private let responder: Task<Void, Never>

  init() {
    let (socket, server) = FakeWebSocket.fakes()
    client = RealtimeClient(
      url: URL(string: "http://localhost:54321/realtime/v1")!,
      options: RealtimeClientOptions(
        disconnectOnEmptyChannelsAfter: .seconds(5),
        handleAppLifecycle: false
      ),
      wsTransport: { _, _ in socket },
      http: HTTPClient(transport: RecordingTransport()),
      clock: clock
    )
    responder = Task {
      for await event in server.events {
        guard let message = event.realtimeMessage, message.event == "phx_join" else { continue }
        server.send(
          RealtimeMessage(
            joinRef: message.joinRef,
            ref: message.ref,
            topic: message.topic,
            event: "phx_reply",
            payload: ["response": ["postgres_changes": .array([])], "status": "ok"]
          )
        )
      }
    }
  }

  deinit {
    responder.cancel()
  }
}

extension RealtimeClient {
  /// The heartbeat a new ``heartbeats()`` stream replays first, if any.
  fileprivate var latestHeartbeat: HeartbeatEvent? { heartbeatFanout.current }

  /// Publishes `event` as the core's `.publishHeartbeat` effect would.
  fileprivate func publishHeartbeat(_ event: HeartbeatEvent) {
    heartbeatFanout.yield(event)
  }

  /// Marks the core record of `channel` as joined with presence on.
  fileprivate func turnPresenceOn(in channel: RealtimeChannel) {
    core.channels[channel.id]?.presenceEnabled = true
  }

  /// Whether the next join of `channel` asks for presence.
  fileprivate func presenceIsOn(in channel: RealtimeChannel) -> Bool? {
    core.channels[channel.id]?.presenceEnabled
  }
}
