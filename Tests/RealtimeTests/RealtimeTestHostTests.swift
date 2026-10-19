import ConcurrencyExtras
import Testing

@testable import Realtime

#if !os(Linux)
  /// The host is the base for deterministic Realtime tests, so it gets its own coverage.
  @Suite
  struct RealtimeTestHostTests {
    @Test
    func subscribeCompletesWhenTheServerConfirmsTheJoin() async throws {
      let host = RealtimeTestHost()
      let channel = await host.client.channel("room")

      async let subscribed: Void = channel.subscribe()
      let join = try await host.receive(event: "phx_join")
      #expect(join.topic == "realtime:room")
      host.confirmJoin(join)
      try await subscribed

      #expect(channel.statusSnapshot == .subscribed)
      await host.waitUntil { host.statuses == [.disconnected, .connecting, .connected] }
      #expect(host.connectCount == 1)
    }

    @Test
    func acknowledgedBroadcastResolvesOnTheServerReply() async throws {
      let host = RealtimeTestHost()
      let channel = await host.client.channel("room") {
        $0.broadcast.acknowledgeBroadcasts = true
      }

      async let subscribed: Void = channel.subscribe()
      host.confirmJoin(try await host.receive(event: "phx_join"))
      try await subscribed

      let push = await channel.track(state: ["name": "ana"])
      let frame = try await host.receive(event: "presence")
      #expect(push.isRunning)
      host.reply(to: frame)

      #expect(try await push() == .ok)
      #expect(!push.isRunning)
    }

    @Test
    func waitUntilFailsFastWhenTheConditionNeverHolds() async {
      let host = RealtimeTestHost()
      await withKnownIssue {
        await host.waitUntil(timeout: .milliseconds(50)) { false }
      }
    }

    @Test
    func disconnectIsObservedWithoutYielding() async throws {
      let host = RealtimeTestHost()
      try await host.client.connect()
      await host.client.disconnect()

      await host.waitUntil { host.statuses.last == .disconnected }
      #expect(host.sockets.first?.isClosed == true)
    }
  }
#endif
