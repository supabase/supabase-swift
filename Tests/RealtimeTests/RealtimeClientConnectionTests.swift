import Clocks
import ConcurrencyExtras
import Foundation
import TestHelpers
import Testing

@testable import Realtime

#if os(Linux)
  // RealtimeClientConnectionTests are disabled on Linux due to timing flakiness.
#else

  @Suite
  struct RealtimeClientConnectionTests {
    @Test
    func reconnectBackoffClampsAnUnusableBaseDelay() {
      // `reconnectDelay` is user-supplied, so the backoff must clamp it into `0...30s`.
      for base: Duration in [.seconds(1_000_000_000), .seconds(-5)] {
        let delay = RealtimeClient.reconnectBackoff(baseDelay: base).backoffDelay(retry: 1)
        #expect(delay >= .zero && delay <= .seconds(30), "baseDelay \(base)")
      }
    }

    // MARK: - Connect

    @Test
    func connectOpensTheSocketAndReportsConnectingThenConnected() async throws {
      let h = Harness(headers: ["apikey": "key"])
      var statuses = await h.client.statusChanges().makeAsyncIterator()

      try await h.client.connect()

      #expect(await h.client.status == .connected)
      #expect(await statuses.next() == .disconnected)
      #expect(await statuses.next() == .connecting)
      #expect(await statuses.next() == .connected)
      let connect = try #require(h.connects.value.first)
      #expect(h.connects.value.count == 1)
      #expect(
        connect.url.absoluteString
          == "ws://localhost:54321/realtime/v1/websocket?apikey=key&vsn=2.0.0"
      )
      #expect(connect.headers["apikey"] == "key")
    }

    @Test
    func connectWhenConnectedIsNoOp() async throws {
      let h = Harness()
      try await h.client.connect()

      try await h.client.connect()

      #expect(await h.client.status == .connected)
      #expect(h.connects.value.count == 1)
    }

    @Test
    func connectFailureThrowsTransportError() async {
      let h = Harness(beforeConnect: { _ in throw URLError(.notConnectedToInternet) })

      let error = await #expect(throws: RealtimeError.self) { try await h.client.connect() }

      #expect(error?.kind == .transport)
      #expect(await h.client.status == .disconnected)
    }

    @Test
    func concurrentConnectsShareOneAttempt() async throws {
      let (gate, open) = AsyncStream<Void>.makeStream()
      let h = Harness(beforeConnect: { _ in
        for await _ in gate { break }
      })

      let first = Task { try await h.client.connect() }
      for await status in await h.client.statusChanges() where status == .connecting { break }
      let second = Task { try await h.client.connect() }
      open.yield()

      try await first.value
      try await second.value
      #expect(await h.client.status == .connected)
      #expect(h.connects.value.count == 1)
    }

    // MARK: - Disconnect

    @Test
    func disconnectClosesTheSocket() async throws {
      let h = Harness()
      try await h.client.connect()

      await h.client.disconnect(reason: "test reason")

      #expect(await h.client.status == .disconnected)
      #expect(h.sockets.value.first?.sentEvents.last == .close(code: nil, reason: "test reason"))
    }

    @Test
    func disconnectWhileConnectingCancelsTheAttempt() async throws {
      let h = Harness(beforeConnect: { _ in try await Task<Never, Never>.never() })

      let connect = Task { try await h.client.connect() }
      for await status in await h.client.statusChanges() where status == .connecting { break }
      await h.client.disconnect()

      await #expect(throws: CancellationError.self) { try await connect.value }
      #expect(await h.client.status == .disconnected)
      #expect(h.sockets.value.isEmpty)
    }

    @Test(arguments: [true, false])
    func aCancelledAttemptCannotTouchTheNextOne(staleAttemptSucceeds: Bool) async throws {
      // Both transport calls block until the test releases them, so the stale outcome lands
      // while the new attempt is still `.connecting`.
      let gates = LockIsolated<[Int: CheckedContinuation<Void, Never>]>([:])
      let (arrivals, arrived) = AsyncStream<Int>.makeStream()
      let h = Harness(beforeConnect: { attempt in
        await withCheckedContinuation { continuation in
          gates.withValue { $0[attempt] = continuation }
          arrived.yield(attempt)
        }
        if attempt == 1, !staleAttemptSucceeds { throw URLError(.cannotConnectToHost) }
      })

      // Attempts are numbered by transport-call order, so wait for each arrival before the
      // next step: attempt 1 is then the stale task and attempt 2 the fresh one.
      let stale = Task { try await h.client.connect() }
      for await attempt in arrivals where attempt == 1 { break }
      await h.client.disconnect()
      let fresh = Task { try await h.client.connect() }
      for await attempt in arrivals where attempt == 2 { break }

      try #require(gates.value[1]).resume()
      await #expect(throws: (any Error).self) { try await stale.value }
      try #require(gates.value[2]).resume()
      try await fresh.value

      #expect(await h.client.status == .connected)
      let current = try #require(h.sockets.value.last)
      #expect(!current.isClosed)
      if staleAttemptSucceeds {
        #expect(h.sockets.value.count == 2)
        #expect(h.sockets.value.first?.closeReason == "Connection cancelled")
      } else {
        #expect(h.sockets.value.count == 1)
      }
    }

    // MARK: - Heartbeat

    @Test
    func releasingTheClientEndsItsStatusAndHeartbeatStreams() async {
      let statuses: AsyncStream<RealtimeClientStatus>
      let beats: AsyncStream<HeartbeatStatus>
      do {
        let h = Harness()
        statuses = await h.client.statusChanges()
        beats = await h.client.heartbeats()
      }

      var statusIterator = statuses.makeAsyncIterator()
      #expect(await statusIterator.next() == .disconnected)
      #expect(await statusIterator.next() == nil)
      var beatIterator = beats.makeAsyncIterator()
      #expect(await beatIterator.next() == nil)
    }

    @Test
    func heartbeatIsSentEachIntervalAndAcknowledged() async throws {
      let h = Harness(heartbeatInterval: .seconds(25))
      try await h.client.connect()
      var beats = await h.client.heartbeats().makeAsyncIterator()

      await h.clock.advance(by: .seconds(25))

      #expect(await beats.next() == .sent)
      let heartbeat = try #require(await h.received("heartbeat", on: 0))
      #expect(heartbeat.topic == "phoenix")
      try h.reply(
        RealtimeMessageV2(
          joinRef: nil, ref: heartbeat.ref, topic: "phoenix", event: ChannelEvent.reply,
          payload: ["status": "ok", "response": [:]]
        ),
        on: 0
      )
      #expect(await beats.next() == .ok)
    }

    @Test
    func missedHeartbeatReportsTimeoutAndReconnects() async throws {
      let h = Harness(heartbeatInterval: .seconds(25), reconnectDelay: .seconds(1))
      try await h.client.connect()
      var beats = await h.client.heartbeats().makeAsyncIterator()
      var statuses = await h.client.statusChanges().makeAsyncIterator()

      await h.clock.advance(by: .seconds(25))
      #expect(await beats.next() == .sent)
      await h.clock.advance(by: .seconds(25))
      #expect(await beats.next() == .timeout)

      #expect(await statuses.next() == .connected)
      #expect(await statuses.next() == .connecting)
      await h.clock.advance(by: .seconds(1))
      #expect(await statuses.next() == .connected)
      #expect(h.connects.value.count == 2)
      #expect(h.sockets.value.first?.isClosed == true)
    }

    // MARK: - Remote close

    @Test
    func applicationCloseCodeDoesNotReconnect() async throws {
      let h = Harness(reconnectDelay: .seconds(1))
      try await h.client.connect()
      var statuses = await h.client.statusChanges().makeAsyncIterator()

      // 4000–4999 signal auth or protocol errors: reconnecting with the same token would loop.
      h.servers.value[0].close(code: 4001, reason: "jwt expired")

      #expect(await statuses.next() == .connected)
      #expect(await statuses.next() == .disconnected)
      await h.clock.advance(by: .seconds(60))
      #expect(h.connects.value.count == 1)
      #expect(await h.client.status == .disconnected)
    }

    @Test
    func transportCloseReconnectsAfterBackoff() async throws {
      let h = Harness(reconnectDelay: .seconds(2))
      try await h.client.connect()
      var statuses = await h.client.statusChanges().makeAsyncIterator()

      h.servers.value[0].close(code: 1001, reason: "going away")

      #expect(await statuses.next() == .connected)
      #expect(await statuses.next() == .connecting)
      // The first wait is in `reconnectDelay/2 ... reconnectDelay`.
      await h.clock.advance(by: .milliseconds(900))
      #expect(h.connects.value.count == 1)
      await h.clock.advance(by: .milliseconds(1100))
      #expect(await statuses.next() == .connected)
      #expect(h.connects.value.count == 2)
    }

    /// Issue #1147: a failed reconnect attempt must schedule another instead of giving up.
    @Test
    func reconnectKeepsRetryingAfterAFailedAttempt() async throws {
      let h = Harness(
        reconnectDelay: .seconds(1),
        beforeConnect: { attempt in
          if attempt == 2 { throw URLError(.notConnectedToInternet) }
        }
      )
      try await h.client.connect()
      var statuses = await h.client.statusChanges().makeAsyncIterator()

      h.servers.value[0].close(code: 1001, reason: "going away")

      #expect(await statuses.next() == .connected)
      #expect(await statuses.next() == .connecting)
      // Attempt 1 waits at most 1s and fails; attempt 2 waits at most 2s more.
      await h.clock.advance(by: .seconds(3))
      #expect(await statuses.next() == .connected)
      #expect(h.connects.value.count == 3)
    }

    /// A frame from a socket that a reconnect already replaced must not touch the new one.
    @Test
    func eventsFromAReplacedSocketAreIgnored() async throws {
      let h = Harness(reconnectDelay: .seconds(1))
      try await h.client.connect()
      let staleGeneration = await h.client.generation
      var statuses = await h.client.statusChanges().makeAsyncIterator()

      h.servers.value[0].close(code: 1001, reason: "going away")
      #expect(await statuses.next() == .connected)
      #expect(await statuses.next() == .connecting)
      await h.clock.advance(by: .seconds(1))
      #expect(await statuses.next() == .connected)
      #expect(h.connects.value.count == 2)

      await h.client.handleSocketEvent(
        .close(code: 1001, reason: "late"), generation: staleGeneration
      )

      #expect(await h.client.status == .connected)
      await h.clock.advance(by: .seconds(60))
      #expect(h.connects.value.count == 2)
    }

    // MARK: - Harness

    /// A client on a `TestClock` whose transport opens a fresh in-memory socket pair per connect.
    private struct Harness {
      let clock: SignalingTestClock
      let client: RealtimeClient
      /// The URL and headers of every transport call, in order.
      let connects: LockIsolated<[(url: URL, headers: [String: String])]>
      /// The client side of every socket opened, in order.
      let sockets: LockIsolated<[FakeWebSocket]>
      /// The server side of every socket opened, in order.
      let servers: LockIsolated<[FakeWebSocket]>

      init(
        headers: [String: String] = [:],
        heartbeatInterval: Duration = .seconds(3600),
        reconnectDelay: Duration = .seconds(1),
        beforeConnect: @escaping @Sendable (_ attempt: Int) async throws -> Void = { _ in }
      ) {
        let clock = SignalingTestClock()
        let connects = LockIsolated<[(url: URL, headers: [String: String])]>([])
        let sockets = LockIsolated<[FakeWebSocket]>([])
        let servers = LockIsolated<[FakeWebSocket]>([])
        self.clock = clock
        self.connects = connects
        self.sockets = sockets
        self.servers = servers
        client = RealtimeClient(
          url: URL(string: "http://localhost:54321/realtime/v1")!,
          options: RealtimeClientOptions(
            headers: headers,
            heartbeatInterval: heartbeatInterval,
            reconnectDelay: reconnectDelay,
            handleAppLifecycle: false
          ),
          wsTransport: { url, headers in
            let attempt = connects.withValue {
              $0.append((url, headers))
              return $0.count
            }
            try await beforeConnect(attempt)
            let (socket, server) = FakeWebSocket.fakes()
            sockets.withValue { $0.append(socket) }
            servers.withValue { $0.append(server) }
            return socket
          },
          http: HTTPClient(transport: RecordingTransport()),
          clock: clock
        )
      }

      /// The next frame for `event` that server `index` receives.
      func received(_ event: String, on index: Int) async -> RealtimeMessageV2? {
        for await frame in servers.value[index].events {
          if case .text(let text) = frame,
            let message = try? RealtimeSerializer().decodeText(text),
            message.event == event
          {
            return message
          }
        }
        return nil
      }

      func reply(_ message: RealtimeMessageV2, on index: Int) throws {
        servers.value[index].send(try RealtimeSerializer().encodeText(message))
      }
    }
  }

#endif
