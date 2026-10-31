//
//  ActorOwnedStateTests.swift
//  RealtimeTests
//

import Clocks
import ConcurrencyExtras
import Foundation
import Helpers
import TestHelpers
import Testing

@testable import Realtime

/// The guarantees of a client that owns all Realtime state: a stream registers before its
/// factory returns, releasing the client ends every stream, and a spent handle degrades.
@Suite(.timeLimit(.minutes(1)))
struct ActorOwnedStateTests {
  /// Rounds of each ordering test. Set `REALTIME_STRESS_ROUNDS` to run more.
  static let stressRounds =
    ProcessInfo.processInfo.environment["REALTIME_STRESS_ROUNDS"].flatMap(Int.init) ?? 200

  // MARK: Ordering

  @Test
  func streamOpenedBeforeSubscribeSeesEveryLaterBroadcast() async throws {
    let host = await RealtimeTestHost()
    #expect(try await missedBroadcasts(on: host, deliveredBy: .inbox) == 0)
  }

  @Test
  func streamOpenedBeforeSubscribeSeesTheFrameThroughTheInbox() async throws {
    let host = await RealtimeTestHost()
    #expect(try await missedBroadcasts(on: host, deliveredBy: .socket) == 0)
  }

  // MARK: Release

  @Test
  func releasedClientEndsStreamsAndDegradesHandles() async throws {
    let servers = LockIsolated<[FakeWebSocket]>([])
    func connectedClientStreams() async throws -> (
      channel: RealtimeChannel,
      clientStatuses: AsyncStream<RealtimeClientStatus>,
      statuses: AsyncStream<RealtimeChannelStatus>,
      broadcasts: AsyncStream<BroadcastMessage>,
      changes: AsyncStream<PostgresChange>
    ) {
      let client = RealtimeClient(
        url: URL(string: "http://localhost:54321/realtime/v1")!,
        options: RealtimeClientOptions(handleAppLifecycle: false),
        wsTransport: { _, _ in
          let (socket, server) = FakeWebSocket.fakes()
          servers.withValue { $0.append(server) }
          return socket
        },
        http: HTTPClient(transport: RecordingTransport()),
        clock: TestClock<Duration>()
      )
      try await client.connect()
      let channel = await client.channel("room")
      return (
        channel,
        await client.statusChanges(),
        await channel.statusChanges(),
        await channel.broadcasts(event: "*"),
        await channel.postgresChanges(table: "todos")
      )
    }
    // The only reference to the client goes away when this returns.
    let (channel, clientStatuses, statuses, broadcasts, changes) =
      try await connectedClientStreams()
    let server = try #require(servers.value.last)

    // Each iteration ends only once the client is gone: its fan-outs finish the streams.
    _ = await clientStatuses.collect()
    #expect(await statuses.collect() == [.unsubscribed])
    #expect(await broadcasts.collect().isEmpty)
    #expect(await changes.collect().isEmpty)

    #expect(channel.client == nil)
    #expect(server.isClosed)
    #expect(server.closeReason == "Client deallocated")
    #expect(await channel.status == .unsubscribed)
    await expectError(.clientReleased) { try await channel.subscribe() }
    await expectError(.clientReleased) {
      try await channel.broadcast(event: "e", payload: ["a": 1] as JSONObject)
    }
  }

  // MARK: Spent handles

  @Test
  func spentHandleStreamsFinishAtOnce() async throws {
    let host = await RealtimeTestHost()
    let channel = await host.client.channel("room")
    try await remove(channel, subscribedWith: host.subscribe(channel), on: host)

    // The status stream does not even replay the last status.
    #expect(await channel.statusChanges().collect().isEmpty)
    #expect(await channel.events().collect().isEmpty)
    #expect(await channel.broadcasts(event: "*").collect().isEmpty)
    #expect(await channel.postgresChanges(table: "todos").collect().isEmpty)
    #expect(await channel.presenceChanges().collect().isEmpty)
    #expect(await channel.presenceStates().collect().isEmpty)
  }

  @Test
  func serverCloseSpendsTheHandle() async throws {
    let host = await RealtimeTestHost()
    let channel = await host.client.channel("room")
    let statuses = await channel.statusChanges()
    let join = try await host.subscribe(channel)

    host.sendClose(for: join)

    // The close finishes the channel's streams, so this ends once the close is applied.
    #expect(await statuses.collect().last == .unsubscribed)
    #expect(await channel.status == .unsubscribed)
    await expectError(.channelRemoved) { try await channel.subscribe() }
    await expectError(.channelRemoved) {
      try await channel.broadcast(event: "e", payload: ["a": 1] as JSONObject)
    }

    let fresh = await host.client.channel("room")
    #expect(fresh !== channel)
    #expect(await host.client.channels.contains(fresh))
    #expect(await !host.client.channels.contains(channel))
    let subscription = Task { try await fresh.subscribe() }
    let rejoin = try await host.receive {
      $0.event == ChannelEvent.join && $0.joinRef != join.joinRef
    }
    host.confirmJoin(rejoin)
    try await subscription.value
    #expect(await fresh.status == .subscribed)
  }

  @Test
  func droppedPostgresStreamLeavesTheJoinAfterOneInboxRound() async throws {
    let host = await RealtimeTestHost()
    let channel = await host.client.channel("db")
    let kept = await channel.postgresChanges(table: "kept")
    let dropped = await channel.postgresChanges(table: "dropped")
    let consumer = Task { for await _ in dropped {} }
    #expect(await host.client.bindings(of: channel).map(\.table) == ["kept", "dropped"])

    consumer.cancel()
    await consumer.value
    await host.client.flushInbox()

    #expect(await host.client.bindings(of: channel).map(\.table) == ["kept"])
    let subscription = Task { try await channel.subscribe() }
    let join = try await host.receive(event: ChannelEvent.join)
    let bindings = join.payload["config"]?.objectValue?["postgres_changes"]?.arrayValue ?? []
    #expect(bindings.map { $0.objectValue?["table"]?.stringValue } == ["kept"])
    subscription.cancel()
    _ = await subscription.result
    withExtendedLifetime(kept) {}
  }

  // MARK: Removal

  @Test
  func neverSubscribedHandleKeepsTheSocketWhenTheLastSubscribedOneGoes() async throws {
    let host = await RealtimeTestHost(
      options: RealtimeClientOptions(
        disconnectOnEmptyChannelsAfter: .seconds(5), handleAppLifecycle: false))
    let subscribed = await host.client.channel("subscribed")
    let join = try await host.subscribe(subscribed)
    let neverSubscribed = await host.client.channel("never-subscribed")

    try await remove(subscribed, subscribedWith: join, on: host)
    await host.clock.advance(by: .seconds(6))
    // An idle disconnect, had one been scheduled, has fired into the inbox by now.
    await host.client.timers.task(for: .idleDisconnect)?.value
    await host.client.flushInbox()

    #expect(await host.client.status == .connected)
    try await host.subscribe(neverSubscribed)
    #expect(host.connectCount == 1)
  }

  @Test
  func removeChannelTwiceDuringSubscribe() async throws {
    let host = await RealtimeTestHost()
    let channel = await host.client.channel("room")
    let subscription = Task { try await channel.subscribe() }
    let join = try await host.receive(event: ChannelEvent.join)

    let first = Task { await host.client.removeChannel(channel) }
    let second = Task { await host.client.removeChannel(channel) }

    await expectError(.channelRemoved) { try await subscription.value }
    _ = try await host.receive(event: ChannelEvent.leave)
    host.sendClose(for: join)
    await first.value
    await second.value

    // Frames leave in order, so once this join is out, a second leave would be too.
    try await host.subscribe(host.client.channel("barrier"))
    #expect(host.frames.filter { $0.event == ChannelEvent.leave }.count == 1)
    #expect(await channel.status == .unsubscribed)
    #expect(await !host.client.hasRecord(for: "room"))
  }

  // MARK: Helpers

  /// How the server's broadcast reaches the client.
  private enum Delivery {
    /// Yielded straight into the inbox, as the reader does.
    case inbox
    /// Sent by the server, read by the reader, then yielded into the inbox.
    case socket
  }

  /// Runs ``stressRounds`` rounds, each on a new channel. A task at background priority opens a
  /// broadcast stream, the test subscribes the channel, and a high-priority task delivers one
  /// broadcast. Returns how many streams did not get exactly that broadcast.
  private func missedBroadcasts(
    on host: RealtimeTestHost, deliveredBy delivery: Delivery
  ) async throws -> Int {
    // The reader and the inbox keep the order the server sent, so once a marker sent after a
    // broadcast reaches the barrier's stream, the broadcast was applied.
    let barrier = await host.client.channel("barrier")
    var markers = await barrier.broadcasts(event: "*").makeAsyncIterator()
    try await host.subscribe(barrier)
    let server = try #require(host.server)
    let generation = await host.client.generation

    var misses = 0
    for round in 0..<Self.stressRounds {
      let channel = await host.client.channel("room-\(round)")
      let broadcasts = await Task(priority: .background) {
        await channel.broadcasts(event: "e")
      }.value

      try await host.subscribe(channel)
      let frame = Self.broadcast(topic: channel.wireTopic, event: "e")
      switch delivery {
      case .inbox:
        await Task(priority: .high) {
          _ = host.client.inbox.yield(.socket(.frame(frame), generation: generation))
        }.value
        await host.client.flushInbox()
      case .socket:
        await Task(priority: .high) { server.send(frame) }.value
        server.send(Self.broadcast(topic: barrier.wireTopic, event: "round-\(round)"))
        let marker = await markers.next()
        #expect(marker?.event == "round-\(round)")
      }
      await host.client.finishStreams(of: channel)

      if await broadcasts.collect().count != 1 { misses += 1 }
    }
    return misses
  }

  /// Removes `channel`, answering its leave the way the server does.
  private func remove(
    _ channel: RealtimeChannel, subscribedWith join: RealtimeMessage, on host: RealtimeTestHost
  ) async throws {
    let removal = Task { await host.client.removeChannel(channel) }
    _ = try await host.receive { $0.event == ChannelEvent.leave && $0.topic == join.topic }
    host.sendClose(for: join)
    await removal.value
  }

  private static func broadcast(topic: String, event: String) -> RealtimeMessage {
    RealtimeMessage(
      joinRef: nil, ref: nil, topic: topic, event: ChannelEvent.broadcast,
      payload: ["type": "broadcast", "event": .string(event), "payload": [:]])
  }
}
