import ConcurrencyExtras
import TestHelpers
import Testing

@testable import Realtime

/// The host is the base for deterministic Realtime tests, so it gets its own coverage.
@Suite
struct RealtimeTestHostTests {
  @Test
  func subscribeCompletesWhenTheServerConfirmsTheJoin() async throws {
    let host = await RealtimeTestHost()
    let channel = await host.client.channel("room")

    async let subscribed: Void = channel.subscribe()
    let join = try await host.receive(event: "phx_join")
    #expect(join.topic == "realtime:room")
    host.confirmJoin(join)
    try await subscribed

    #expect(await channel.status == .subscribed)
    await host.waitUntil { host.statuses == [.disconnected, .connecting, .connected] }
    #expect(host.connectCount == 1)
  }

  @Test
  func acknowledgedBroadcastResolvesOnTheServerReply() async throws {
    let host = await RealtimeTestHost()
    let channel = await host.client.channel("room") {
      $0.broadcast.acknowledge = true
    }

    async let subscribed: Void = channel.subscribe()
    host.confirmJoin(try await host.receive(event: "phx_join"))
    try await subscribed

    async let push: Void = channel.track(["name": "ana"] as JSONObject)
    let frame = try await host.receive(event: "presence")
    #expect(await channel.pendingPushes.count == 1)
    host.reply(to: frame)

    try await push
    #expect(await channel.pendingPushes.isEmpty)
  }

  @Test
  func waitUntilFailsFastWhenTheConditionNeverHolds() async {
    let host = await RealtimeTestHost()
    await withKnownIssue {
      await host.waitUntil(timeout: .milliseconds(50)) { false }
    }
  }

  @Test
  func disconnectIsObservedWithoutYielding() async throws {
    let host = await RealtimeTestHost()
    try await host.client.connect()
    await host.client.disconnect()

    await host.waitUntil { host.statuses.last == .disconnected }
    #expect(host.sockets.first?.isClosed == true)
  }

  @Test
  func topicIsTheUserNameAndTheWireTopicIsPrefixed() async throws {
    let host = await RealtimeTestHost()
    let channel = await host.client.channel("room")

    #expect(channel.topic == "room")
    #expect(await host.client.channels["room"] === channel)

    async let subscribed: Void = channel.subscribe()
    let join = try await host.receive(event: "phx_join")
    #expect(join.topic == "realtime:room")
    host.confirmJoin(join)
    try await subscribed
    #expect(await channel.status == .subscribed)
  }

  @Test
  func aTopicThatStartsWithRealtimeIsStillPrefixedOnTheWire() async throws {
    let host = await RealtimeTestHost()
    let channel = await host.client.channel("realtime:room")

    #expect(channel.topic == "realtime:room")

    async let subscribed: Void = channel.subscribe()
    let join = try await host.receive(event: "phx_join")
    #expect(join.topic == "realtime:realtime:room")
    host.confirmJoin(join)
    try await subscribed
    #expect(await channel.status == .subscribed)
  }
}
