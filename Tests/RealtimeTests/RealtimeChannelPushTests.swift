import Clocks
import ConcurrencyExtras
import Foundation
import TestHelpers
import Testing

@testable import Realtime

#if os(Linux)
  // RealtimeChannelPushTests are disabled on Linux due to timing flakiness.
#else

  @Suite
  struct RealtimeChannelPushTests {
    @Test
    func broadcastWithoutAcknowledgementReturnsOnceSent() async throws {
      let h = Harness()
      let channel = await h.client.channel("room")
      _ = try await h.subscribe(channel)

      try await channel.broadcast(event: "cursor", message: ["x": 1] as JSONObject)

      #expect(h.socket.sentEvents.contains { if case .binary = $0 { true } else { false } })
    }

    @Test
    func broadcastBeforeSubscribeThrowsNotSubscribed() async {
      let h = Harness()
      let channel = await h.client.channel("room")

      let error = await #expect(throws: RealtimeError.self) {
        try await channel.broadcast(event: "cursor", message: ["x": 1] as JSONObject)
      }
      #expect(error?.kind == .notSubscribed)
    }

    @Test
    func acknowledgedPushReturnsOnServerReply() async throws {
      let h = Harness()
      let channel = await h.client.channel("room") { $0.broadcast.acknowledgeBroadcasts = true }
      let join = try await h.subscribe(channel)

      let push = Task { try await channel.track(state: ["online": true]) }
      let frame = try #require(await h.received(ChannelEvent.presence))
      #expect(await channel.pendingPushes.count == 1)
      try h.reply(h.pushReply(to: frame, join: join, payload: ["status": "ok", "response": [:]]))

      try await push.value
      #expect(await channel.pendingPushes.isEmpty)
    }

    @Test
    func errorReplyThrowsTheServerReason() async throws {
      let h = Harness()
      let channel = await h.client.channel("room") { $0.broadcast.acknowledgeBroadcasts = true }
      let join = try await h.subscribe(channel)

      let push = Task { try await channel.track(state: ["online": true]) }
      let frame = try #require(await h.received(ChannelEvent.presence))
      try h.reply(
        h.pushReply(
          to: frame, join: join,
          payload: ["status": "error", "response": ["reason": "payload_size_exceeded"]]
        )
      )

      let error = await #expect(throws: RealtimeError.self) { try await push.value }
      #expect(error?.kind == .payloadTooLarge)
      #expect(error?.isRetryable == false)
    }

    @Test
    func errorReplyWithACodedReasonCarriesTheServerCode() async throws {
      let h = Harness()
      let channel = await h.client.channel("room") { $0.broadcast.acknowledgeBroadcasts = true }
      let join = try await h.subscribe(channel)

      let push = Task { try await channel.track(state: ["online": true]) }
      let frame = try #require(await h.received(ChannelEvent.presence))
      try h.reply(
        h.pushReply(
          to: frame, join: join,
          payload: [
            "status": "error", "response": ["reason": "Unauthorized: presence is private"],
          ]
        )
      )

      let error = await #expect(throws: RealtimeError.self) { try await push.value }
      #expect(error?.kind == .server)
      #expect(error?.serverCode == .unauthorized)
      #expect(error?.message == "Unauthorized: presence is private")
    }

    @Test
    func pushWithoutReplyThrowsTimeout() async throws {
      let h = Harness(timeout: .seconds(10))
      let channel = await h.client.channel("room") { $0.broadcast.acknowledgeBroadcasts = true }
      _ = try await h.subscribe(channel)

      let push = Task { try await channel.track(state: ["online": true]) }
      _ = try #require(await h.received(ChannelEvent.presence))
      await h.clock.advance(by: .seconds(10))

      let error = await #expect(throws: RealtimeError.self) { try await push.value }
      #expect(error?.kind == .timeout)
      #expect(await channel.pendingPushes.isEmpty)
    }

    @Test
    func cancellingTheAwaitingTaskThrowsCancellationErrorAndDropsTheSlot() async throws {
      let h = Harness()
      let channel = await h.client.channel("room") { $0.broadcast.acknowledgeBroadcasts = true }
      _ = try await h.subscribe(channel)

      let push = Task { try await channel.track(state: ["online": true]) }
      _ = try #require(await h.received(ChannelEvent.presence))
      push.cancel()

      await #expect(throws: CancellationError.self) { try await push.value }
      #expect(await channel.pendingPushes.isEmpty)
    }

    @Test
    func disconnectFailsPendingPushWithNotConnected() async throws {
      let h = Harness()
      let channel = await h.client.channel("room") { $0.broadcast.acknowledgeBroadcasts = true }
      _ = try await h.subscribe(channel)

      let push = Task { try await channel.track(state: ["online": true]) }
      _ = try #require(await h.received(ChannelEvent.presence))
      await h.client.disconnect()

      let error = await #expect(throws: RealtimeError.self) { try await push.value }
      #expect(error?.kind == .notConnected)
    }

    @Test
    func serverCloseFailsPendingPushWithChannelClosedByServer() async throws {
      let h = Harness()
      let channel = await h.client.channel("room") { $0.broadcast.acknowledgeBroadcasts = true }
      let join = try await h.subscribe(channel)

      let push = Task { try await channel.track(state: ["online": true]) }
      _ = try #require(await h.received(ChannelEvent.presence))
      try h.reply(
        RealtimeMessageV2(
          joinRef: join.ref, ref: nil, topic: channel.topic, event: ChannelEvent.close,
          payload: [:]
        )
      )

      let error = await #expect(throws: RealtimeError.self) { try await push.value }
      #expect(error?.kind == .channelClosedByServer)
    }

    /// A client on a `TestClock`, connected to an in-memory server socket the test drives.
    private struct Harness {
      let clock: SignalingTestClock
      let socket: FakeWebSocket
      let server: FakeWebSocket
      let client: RealtimeClient

      init(timeout: Duration = RealtimeClientOptions.defaultTimeout) {
        let clock = SignalingTestClock()
        let (socket, server) = FakeWebSocket.fakes()
        self.clock = clock
        self.socket = socket
        self.server = server
        client = RealtimeClient(
          url: URL(string: "http://localhost:54321/realtime/v1")!,
          options: RealtimeClientOptions(
            heartbeatInterval: .seconds(3600),
            timeout: timeout,
            handleAppLifecycle: false
          ),
          wsTransport: { _, _ in socket },
          http: HTTPClient(transport: RecordingTransport()),
          clock: clock
        )
      }

      /// The next frame for `event` the server receives.
      func received(_ event: String) async -> RealtimeMessageV2? {
        for await frame in server.events {
          if case .text(let text) = frame,
            let message = try? RealtimeSerializer().decodeText(text),
            message.event == event
          {
            return message
          }
        }
        return nil
      }

      func reply(_ message: RealtimeMessageV2) throws {
        server.send(try RealtimeSerializer().encodeText(message))
      }

      func pushReply(
        to frame: RealtimeMessageV2, join: RealtimeMessageV2, payload: JSONObject
      ) -> RealtimeMessageV2 {
        RealtimeMessageV2(
          joinRef: join.ref, ref: frame.ref, topic: frame.topic, event: ChannelEvent.reply,
          payload: payload
        )
      }

      /// Subscribes `channel`, answering its `phx_join` the way the server does. Returns the join.
      func subscribe(_ channel: RealtimeChannel) async throws -> RealtimeMessageV2 {
        async let subscription: Void = channel.subscribe()
        let join = try #require(await received(ChannelEvent.join))
        try reply(
          pushReply(
            to: join, join: join,
            payload: ["status": "ok", "response": ["postgres_changes": .array([])]]
          )
        )
        try await subscription
        return join
      }
    }
  }

#endif
