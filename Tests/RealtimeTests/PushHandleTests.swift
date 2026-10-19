import Clocks
import ConcurrencyExtras
import Foundation
import TestHelpers
import Testing

@testable import Realtime

@Suite
struct PushHandleTests {
  @Test
  func pushStatusRawValues() {
    #expect(PushStatus.ok.rawValue == "ok")
    #expect(PushStatus.error.rawValue == "error")
    #expect(PushStatus.timeout.rawValue == "timeout")
    #expect(PushStatus(rawValue: "ok") == .ok)
    #expect(PushStatus(rawValue: "invalid").rawValue == "invalid")
  }

  @Test
  func newHandleIsRunning() {
    let handle = PushHandle()

    #expect(handle.isRunning)
    #expect(handle.error == nil)
  }

  @Test
  func resolveSettlesWithStatus() async throws {
    let handle = PushHandle()
    handle.resolve(.ok)

    #expect(!handle.isRunning)
    #expect(handle.error == nil)
    #expect(try await handle() == .ok)
  }

  @Test
  func resolveWakesAWaitingCaller() async throws {
    let handle = PushHandle()
    let waiter = Task { try await handle() }

    handle.resolve(.timeout)

    #expect(try await waiter.value == .timeout)
  }

  @Test
  func everyWaiterReceivesTheOutcome() async throws {
    let handle = PushHandle()
    async let first = handle()
    async let second = handle()

    handle.resolve(.ok)

    #expect(try await first == .ok)
    #expect(try await second == .ok)
  }

  @Test
  func failSettlesWithError() async {
    let handle = PushHandle()
    handle.fail(RealtimeError.notConnected)

    #expect(!handle.isRunning)
    #expect((handle.error as? RealtimeError)?.kind == .notConnected)
    let error = await #expect(throws: RealtimeError.self) { try await handle() }
    #expect(error?.kind == .notConnected)
  }

  @Test
  func cancelThrowsCancellationErrorToEveryWaiter() async {
    let handle = PushHandle()
    let waiter = Task { try await handle() }

    handle.cancel()

    #expect(!handle.isRunning)
    #expect(handle.error == nil)
    await #expect(throws: CancellationError.self) { try await waiter.value }
    await #expect(throws: CancellationError.self) { try await handle() }
  }

  @Test
  func cancellingTheAwaitingTaskReturnsPromptlyAndLeavesTheHandleRunning() async {
    let handle = PushHandle()
    let waiter = Task { try await handle() }

    waiter.cancel()

    await #expect(throws: CancellationError.self) { try await waiter.value }
    #expect(handle.isRunning)
  }

  @Test
  func factoriesReturnSettledHandles() async throws {
    let resolved = PushHandle.resolved(.ok)
    #expect(!resolved.isRunning)
    #expect(try await resolved() == .ok)

    let failed = PushHandle.failed(RealtimeError.notSubscribed)
    #expect(!failed.isRunning)
    let error = await #expect(throws: RealtimeError.self) { try await failed() }
    #expect(error?.kind == .notSubscribed)
  }

  @Test
  func onlyTheFirstOutcomeCounts() async throws {
    let handle = PushHandle()

    handle.resolve(.ok)
    handle.fail(RealtimeError.notConnected)
    handle.resolve(.timeout)
    handle.cancel()

    #expect(handle.error == nil)
    #expect(try await handle() == .ok)
  }
}

#if os(Linux)
  // RealtimeChannelPushTests are disabled on Linux due to timing flakiness.
#else

  @Suite
  struct RealtimeChannelPushTests {
    @Test
    func broadcastWithoutAcknowledgementResolvesImmediately() async throws {
      let h = Harness()
      let channel = await h.client.channel("room")
      _ = try await h.subscribe(channel)

      let push = await channel.broadcast(event: "cursor", message: ["x": 1])

      #expect(!push.isRunning)
      #expect(try await push() == .ok)
      #expect(h.socket.sentEvents.contains { if case .binary = $0 { true } else { false } })
    }

    @Test
    func broadcastBeforeSubscribeFailsWithNotSubscribed() async {
      let h = Harness()
      let channel = await h.client.channel("room")

      let push = await channel.broadcast(event: "cursor", message: ["x": 1])

      let error = await #expect(throws: RealtimeError.self) { try await push() }
      #expect(error?.kind == .notSubscribed)
    }

    @Test
    func acknowledgedPushResolvesOnServerReply() async throws {
      let h = Harness()
      let channel = await h.client.channel("room") { $0.broadcast.acknowledgeBroadcasts = true }
      let join = try await h.subscribe(channel)

      let push = await channel.track(state: ["online": true])
      #expect(push.isRunning)

      let frame = try #require(await h.received(ChannelEvent.presence))
      try h.reply(h.pushReply(to: frame, join: join, payload: ["status": "ok", "response": [:]]))

      #expect(try await push() == .ok)
    }

    @Test
    func errorReplyFailsWithAckError() async throws {
      let h = Harness()
      let channel = await h.client.channel("room") { $0.broadcast.acknowledgeBroadcasts = true }
      let join = try await h.subscribe(channel)

      let push = await channel.track(state: ["online": true])
      let frame = try #require(await h.received(ChannelEvent.presence))
      try h.reply(
        h.pushReply(
          to: frame, join: join,
          payload: ["status": "error", "response": ["reason": "payload_size_exceeded"]]
        )
      )

      let error = await #expect(throws: RealtimeError.self) { try await push() }
      #expect(error?.kind == .payloadTooLarge)
      #expect((push.error as? RealtimeError)?.kind == .payloadTooLarge)
    }

    @Test
    func pushWithoutReplyTimesOut() async throws {
      let h = Harness(timeout: .seconds(10))
      let channel = await h.client.channel("room") { $0.broadcast.acknowledgeBroadcasts = true }
      _ = try await h.subscribe(channel)

      let push = await channel.track(state: ["online": true])
      _ = try #require(await h.received(ChannelEvent.presence))
      await h.clock.advance(by: .seconds(10))

      #expect(try await push() == .timeout)
      #expect(push.error == nil)
    }

    @Test
    func disconnectFailsPendingPushWithNotConnected() async throws {
      let h = Harness()
      let channel = await h.client.channel("room") { $0.broadcast.acknowledgeBroadcasts = true }
      _ = try await h.subscribe(channel)

      let push = await channel.track(state: ["online": true])
      await h.client.disconnect()

      let error = await #expect(throws: RealtimeError.self) { try await push() }
      #expect(error?.kind == .notConnected)
    }

    @Test
    func serverCloseFailsPendingPushWithChannelClosedByServer() async throws {
      let h = Harness()
      let channel = await h.client.channel("room") { $0.broadcast.acknowledgeBroadcasts = true }
      let join = try await h.subscribe(channel)

      let push = await channel.track(state: ["online": true])
      try h.reply(
        RealtimeMessageV2(
          joinRef: join.ref, ref: nil, topic: channel.topic, event: ChannelEvent.close,
          payload: [:]
        )
      )

      let error = await #expect(throws: RealtimeError.self) { try await push() }
      #expect(error?.kind == .channelClosedByServer)
    }

    /// A client on a `TestClock`, connected to an in-memory server socket the test drives.
    private struct Harness {
      let clock: TestClock<Duration>
      let socket: FakeWebSocket
      let server: FakeWebSocket
      let client: RealtimeClient

      init(timeout: Duration = RealtimeClientOptions.defaultTimeout) {
        let clock = TestClock<Duration>()
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
