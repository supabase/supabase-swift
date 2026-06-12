import ConcurrencyExtras
import Foundation
import TestHelpers
import XCTest

@testable import Realtime

/// Regression tests for SDK-959: deaf-socket stalls on cold-start subscribe.
///
/// These tests intentionally mimic the production timing profile — a
/// transport that takes real time to connect and a server that delivers
/// frames asynchronously on a separate queue (like URLSession's delegate
/// queue) — instead of the synchronous delivery of `FakeWebSocket`, which
/// masks the races involved. They run against the real clock with compressed
/// intervals, deliberately NOT under `withMainSerialExecutor`.
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
final class RealtimeColdStartTests: XCTestCase {
  let url = URL(string: "http://localhost:54321/realtime/v1")!
  let apiKey = "anon.api.key"

  override func setUp() {
    super.setUp()
    _clock = ContinuousClock()
  }

  private func makeClient(socket: AsyncFakeWebSocket) -> RealtimeClientV2 {
    RealtimeClientV2(
      url: url,
      options: RealtimeClientOptions(
        headers: ["apikey": apiKey],
        // Long heartbeat so heartbeat machinery can't mask subscribe stalls
        // by triggering recovery reconnects on slow CI machines.
        heartbeatInterval: 10,
        reconnectDelay: 0.1,
        timeoutInterval: 2,
        accessToken: { "token" }
      ),
      wsTransport: { _, _ in
        // Simulate real connection latency.
        try await Task.sleep(nanoseconds: 20_000_000)
        return socket
      },
      http: HTTPClientMock()
    )
  }

  /// Polls `condition` until it holds or `timeout` elapses.
  private func waitUntil(
    timeout: TimeInterval = 5.0,
    _ condition: @escaping @Sendable () -> Bool
  ) async {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if condition() { return }
      try? await Task.sleep(nanoseconds: 10_000_000)
    }
  }

  /// Reporter's flow from SDK-959: cold client, one channel, postgresChange
  /// streams consumed in detached tasks, then `subscribeWithError()`.
  /// With the deaf-socket bug this throws `maxRetryAttemptsReached` because
  /// the `phx_join` reply is never seen.
  func testColdStartSubscribe_realTimingProfile() async throws {
    for iteration in 1...5 {
      let socket = AsyncFakeWebSocket()
      socket.serverResponder = AsyncFakeWebSocket.realtimeServerResponder()

      let sut = makeClient(socket: socket)
      defer { sut.disconnect() }

      let channel = sut.channel("library-realtime")
      let libros = channel.postgresChange(AnyAction.self, schema: "library", table: "libros")
      let files = channel.postgresChange(AnyAction.self, schema: "library", table: "libro_files")

      let t1 = Task { for await _ in libros {} }
      let t2 = Task { for await _ in files {} }
      defer {
        t1.cancel()
        t2.cancel()
      }

      do {
        try await channel.subscribeWithError()
      } catch {
        XCTFail("Iteration \(iteration): subscribe failed: \(error)")
        return
      }

      XCTAssertEqual(channel.status, .subscribed, "Iteration \(iteration)")
    }
  }

  /// Two channels subscribing concurrently at cold start: both call
  /// `ensureSocketConnected` → concurrent `connect()` → ConnectionManager's
  /// `.connecting` wait path returns the same connection to both callers →
  /// both used to call `handleConnected(conn:)`, reading `conn.events` twice
  /// and leaving the socket deaf (no heartbeat acks, no phx_join replies) —
  /// the SDK-959 stall, thrown here as `maxRetryAttemptsReached`.
  func testColdStartConcurrentSubscribes_doNotGoDeaf() async throws {
    for iteration in 1...5 {
      let socket = AsyncFakeWebSocket()
      socket.serverResponder = AsyncFakeWebSocket.realtimeServerResponder()

      let sut = makeClient(socket: socket)
      defer { sut.disconnect() }

      let channel1 = sut.channel("room-1")
      let channel2 = sut.channel("room-2")

      async let s1: Void = channel1.subscribeWithError()
      async let s2: Void = channel2.subscribeWithError()

      do {
        _ = try await (s1, s2)
      } catch {
        XCTFail("Iteration \(iteration): subscribe failed: \(error)")
        return
      }

      XCTAssertEqual(channel1.status, .subscribed, "Iteration \(iteration)")
      XCTAssertEqual(channel2.status, .subscribed, "Iteration \(iteration)")
    }
  }

  /// A heartbeat left pending on a connection that errors out must not be
  /// misread as a timeout on the replacement connection. Before the fix,
  /// `pendingHeartbeatRef` survived reconnects, so the new connection's first
  /// heartbeat reported `.timeout` and tore down a healthy socket —
  /// perpetuating the reconnect cycle indefinitely.
  ///
  /// Detection strategy: instead of asserting on specific heartbeat statuses
  /// (which are sensitive to whether the reconnect was triggered by the
  /// malformed frame or by the heartbeat timer itself), we verify that after
  /// the first reconnect the socket count stabilises. With the bug, socket 2's
  /// first heartbeat immediately times out → a second reconnect → socket 3 →
  /// etc. With the fix, socket 2 stays connected.
  func testPendingHeartbeatDoesNotLeakAcrossReconnect() async throws {
    let sockets = LockIsolated<[AsyncFakeWebSocket]>([])

    let sut = RealtimeClientV2(
      url: url,
      options: RealtimeClientOptions(
        headers: ["apikey": apiKey],
        heartbeatInterval: 0.2,
        reconnectDelay: 0.05,
        timeoutInterval: 5,
        accessToken: { "token" }
      ),
      wsTransport: { _, _ in
        let socket = AsyncFakeWebSocket()
        // Every socket after the first acks heartbeats normally so that a
        // healthy post-reconnect connection never times out on its own.
        if sockets.value.count >= 1 {
          socket.serverResponder = AsyncFakeWebSocket.realtimeServerResponder()
        }
        sockets.withValue { $0.append(socket) }
        return socket
      },
      http: HTTPClientMock()
    )
    defer { sut.disconnect() }

    let heartbeatStatuses = LockIsolated<[HeartbeatStatus]>([])
    let subscription = sut.onHeartbeat { status in
      heartbeatStatuses.withValue { $0.append(status) }
    }
    defer { subscription.cancel() }

    await sut.connect()

    // Wait for the first heartbeat to be sent (ref stays pending — socket 0
    // never acks). The reconnect may be triggered by either the malformed frame
    // or the second heartbeat timeout; both exercise the same code path.
    await waitUntil { heartbeatStatuses.value.contains(.sent) }

    // Inject a malformed frame: listenForMessages throws → handleError →
    // initiates reconnect.
    sockets.value[0].receiveFromServer(.text("not a valid frame"))

    // Wait for the first reconnect to complete.
    await waitUntil(timeout: 5) { sockets.value.count >= 2 }
    guard sockets.value.count >= 2 else {
      return XCTFail("No reconnect within 5 s — socket count: \(sockets.value.count)")
    }

    // Record the count right after the first reconnect. If pendingHeartbeatRef
    // leaked into socket 2, its first heartbeat (0.2 s away) immediately times
    // out → another reconnect → socket count grows. Allow 5 heartbeat cycles
    // plus a buffer for scheduling jitter to observe this.
    let countAfterFirstReconnect = sockets.value.count
    await waitUntil(timeout: 0.2 * 5 + 1.0) {
      sockets.value.count > countAfterFirstReconnect
    }

    XCTAssertEqual(
      sockets.value.count, countAfterFirstReconnect,
      """
      Perpetual reconnects detected — pendingHeartbeatRef likely leaked \
      into the replacement connection: \(heartbeatStatuses.value)
      """
    )
  }
}

/// A `WebSocket` fake whose server side delivers frames asynchronously on a
/// serial queue, standing in for URLSession's delegate queue. Events received
/// before `onEvent` is attached are buffered and replayed on attach, exactly
/// like `URLSessionWebSocket`.
final class AsyncFakeWebSocket: WebSocket, @unchecked Sendable {
  struct MutableState {
    var isClosed: Bool = false
    var onEvent: (@Sendable (WebSocketEvent) -> Void)?
    var eventBuffer: [WebSocketEvent] = []
    var sentMessages: [RealtimeMessageV2] = []
    var closeCode: Int?
    var closeReason: String?
  }

  let mutableState = LockIsolated(MutableState())
  let deliveryQueue = DispatchQueue(label: "AsyncFakeWebSocket.delivery")

  /// Server-side autoresponder, invoked off the sender's thread.
  var serverResponder: (@Sendable (RealtimeMessageV2, AsyncFakeWebSocket) -> Void)?

  var closeCode: Int? { mutableState.value.closeCode }
  var closeReason: String? { mutableState.value.closeReason }
  var isClosed: Bool { mutableState.value.isClosed }
  let `protocol`: String = ""

  var sentMessages: [RealtimeMessageV2] { mutableState.value.sentMessages }

  /// Standard Realtime server behavior: acks heartbeats, confirms joins.
  static func realtimeServerResponder()
    -> @Sendable (RealtimeMessageV2, AsyncFakeWebSocket) -> Void
  {
    { message, socket in
      switch message.event {
      case "heartbeat":
        socket.reply(
          RealtimeMessageV2(
            joinRef: nil,
            ref: message.ref,
            topic: "phoenix",
            event: "phx_reply",
            payload: ["response": [:], "status": "ok"]
          )
        )
      case "phx_join":
        socket.reply(
          RealtimeMessageV2(
            joinRef: message.joinRef,
            ref: message.ref,
            topic: message.topic,
            event: "phx_reply",
            payload: [
              "response": [
                "postgres_changes": [
                  ["id": 1, "event": "*", "schema": "library", "table": "libros"],
                  ["id": 2, "event": "*", "schema": "library", "table": "libro_files"],
                ]
              ],
              "status": "ok",
            ]
          )
        )
      default:
        break
      }
    }
  }

  func send(_ text: String) {
    guard !isClosed else { return }
    let serializer = RealtimeSerializer()
    guard let message = try? serializer.decodeText(text) else { return }
    mutableState.withValue { $0.sentMessages.append(message) }
    // The server processes the message asynchronously, like a real network.
    deliveryQueue.async { [weak self] in
      guard let self else { return }
      self.serverResponder?(message, self)
    }
  }

  func send(_ binary: Data) {}

  func close(code: Int?, reason: String?) {
    mutableState.withValue {
      guard !$0.isClosed else { return }
      $0.isClosed = true
      $0.closeCode = code
      $0.closeReason = reason
    }
    // Like URLSession, the .close event arrives later on the delegate queue.
    deliveryQueue.async { [weak self] in
      self?.receiveFromServer(.close(code: code ?? 1005, reason: reason ?? ""))
    }
  }

  /// Server pushes an event to the client; delivered through onEvent if
  /// attached, otherwise buffered and replayed on attach.
  func receiveFromServer(_ event: WebSocketEvent) {
    mutableState.withValue {
      if let onEvent = $0.onEvent {
        onEvent(event)
      } else {
        $0.eventBuffer.append(event)
      }
      if case .close(let code, let reason) = event {
        $0.onEvent = nil
        $0.isClosed = true
        $0.closeCode = code
        $0.closeReason = reason
        $0.eventBuffer.removeAll()
      }
    }
  }

  func reply(_ message: RealtimeMessageV2) {
    let serializer = RealtimeSerializer()
    let text = try! serializer.encodeText(message)
    receiveFromServer(.text(text))
  }

  var onEvent: (@Sendable (WebSocketEvent) -> Void)? {
    get { mutableState.value.onEvent }
    set {
      mutableState.withValue { state in
        state.onEvent = newValue
        if let onEvent = newValue, !state.eventBuffer.isEmpty {
          let buffered = state.eventBuffer
          state.eventBuffer.removeAll()
          for event in buffered { onEvent(event) }
        }
      }
    }
  }
}
