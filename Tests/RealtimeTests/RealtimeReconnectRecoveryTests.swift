import ConcurrencyExtras
import Foundation
import TestHelpers
import Testing

@testable import Realtime
@testable import RealtimeV2

/// Regression tests for issue #1145: after a failed auto-reconnect a client
/// could reach a state where no subscribe ever converged again.
///
/// Uses the same real-timing profile as `RealtimeColdStartTests`
/// (`AsyncFakeWebSocket` + real clock with compressed intervals) because the
/// defects are lifecycle races.
@Suite
struct RealtimeReconnectRecoveryTests {
  let url = URL(string: "http://localhost:54321/realtime/v1")!
  let apiKey = "anon.api.key"

  private func makeOptions(timeoutInterval: TimeInterval = 3) -> RealtimeClientOptions {
    RealtimeClientOptions(
      headers: ["apikey": apiKey],
      // Long heartbeat so heartbeat machinery can't interfere.
      heartbeatInterval: 10,
      reconnectDelay: 0.05,
      timeoutInterval: timeoutInterval,
      accessToken: { "token" }
    )
  }

  /// Defect 1 in #1145: `sawReconnecting` was cleared only on `.connected`.
  /// When the single auto-reconnect attempt failed (network still down), the
  /// latch stayed armed, and the next successful `connect()` — e.g. from a
  /// channel's `connectOnSubscribe` — was misclassified as a reconnect
  /// completion. The resulting `rejoinChannels()` reset cancelled the very
  /// join that connect was performing, surfacing as `CancellationError`.
  @Test
  func subscribeConvergesAfterFailedAutoReconnect() async throws {
    let sockets = LockIsolated<[AsyncFakeWebSocket]>([])
    let connectAttempts = LockIsolated(0)

    let sut = RealtimeClientV2(
      url: url,
      options: makeOptions(),
      wsTransport: { _, _ in
        let attempt = connectAttempts.withValue { count -> Int in
          count += 1
          return count
        }
        // Attempt 2 is the automatic reconnect — the network is still down.
        if attempt == 2 {
          throw RealtimeError("network down")
        }
        let socket = AsyncFakeWebSocket()
        socket.serverResponder = AsyncFakeWebSocket.realtimeServerResponder()
        sockets.withValue { $0.append(socket) }
        return socket
      },
      http: HTTPClientMock(),
      clock: ContinuousClock()
    )
    defer { sut.disconnect() }

    let channel = sut.channel("room-1")
    try await channel.subscribeWithError()
    #expect(channel.status == .subscribed)

    // Outage: the socket errors out, the single auto-reconnect attempt fails.
    sockets.value[0].receiveFromServer(.text("not a valid frame"))
    let parkedDisconnected = await waitUntil(timeout: 5) {
      connectAttempts.value >= 2 && sut.status == .disconnected
    }
    guard parkedDisconnected else {
      Issue.record("Client did not settle in .disconnected after failed reconnect")
      return
    }

    // Network is back. A supervisor rebuilds with a fresh channel;
    // `connectOnSubscribe` brings the socket up. Before the fix, the stale
    // latch fired `rejoinChannels()`, whose reset cancelled this in-flight
    // join (`CancellationError`).
    let channel2 = sut.channel("room-2")
    do {
      try await channel2.subscribeWithError()
    } catch {
      Issue.record("Subscribe after failed auto-reconnect threw: \(error)")
      return
    }
    #expect(channel2.status == .subscribed)
  }

  /// Defect 3 in #1145: `phx_close` was routed by topic only. A close
  /// belonging to a previous incarnation's join killed the current
  /// subscription on the same topic.
  @Test
  func stalePhxCloseDoesNotKillCurrentSubscription() async throws {
    let sockets = LockIsolated<[AsyncFakeWebSocket]>([])

    let sut = RealtimeClientV2(
      url: url,
      options: makeOptions(),
      wsTransport: { _, _ in
        let socket = AsyncFakeWebSocket()
        socket.serverResponder = AsyncFakeWebSocket.realtimeServerResponder()
        sockets.withValue { $0.append(socket) }
        return socket
      },
      http: HTTPClientMock(),
      clock: ContinuousClock()
    )
    defer { sut.disconnect() }

    let channel = sut.channel("room-close")
    try await channel.subscribeWithError()
    #expect(channel.status == .subscribed)

    let socket = sockets.value[0]
    let joinRef = socket.sentMessages.first { $0.event == "phx_join" }?.ref
    #expect(joinRef != nil)

    // A phx_close for a *different* join_ref (a stale incarnation) arrives.
    socket.reply(
      RealtimeMessageV2(
        joinRef: "stale-join-ref",
        ref: nil,
        topic: channel.topic,
        event: "phx_close",
        payload: [:]
      )
    )

    // Give the frame time to route; the channel must survive it.
    try? await Task.sleep(nanoseconds: 300_000_000)
    #expect(channel.status == .subscribed, "Stale phx_close killed the current subscription")
    #expect(sut.channels[channel.topic] != nil, "Stale phx_close removed the channel")

    // A phx_close for the *current* join_ref still tears the channel down.
    socket.reply(
      RealtimeMessageV2(
        joinRef: joinRef,
        ref: nil,
        topic: channel.topic,
        event: "phx_close",
        payload: [:]
      )
    )
    await waitUntil(timeout: 2) { channel.status == .unsubscribed }
    #expect(channel.status == .unsubscribed)
  }

  /// Hazard 4 in #1145: `unsubscribe()` on a dead socket pushed `phx_leave`
  /// into the send buffer (flushed verbatim into the next connection) and
  /// waited the full timeout for a `phx_close` that could never arrive.
  @Test
  func unsubscribeOnDeadSocketSkipsLeaveAndDoesNotStall() async throws {
    let sockets = LockIsolated<[AsyncFakeWebSocket]>([])

    let sut = RealtimeClientV2(
      url: url,
      options: makeOptions(timeoutInterval: 3),
      wsTransport: { _, _ in
        let socket = AsyncFakeWebSocket()
        socket.serverResponder = AsyncFakeWebSocket.realtimeServerResponder()
        sockets.withValue { $0.append(socket) }
        return socket
      },
      http: HTTPClientMock(),
      clock: ContinuousClock()
    )
    defer { sut.disconnect() }

    let channel = sut.channel("room-leave")
    try await channel.subscribeWithError()
    #expect(channel.status == .subscribed)

    // Server closes with an application-level code (4000–4999): no reconnect
    // is attempted, the client parks in .disconnected, and the channel is
    // left stale-`.subscribed`.
    sockets.value[0].receiveFromServer(.close(code: 4001, reason: "auth"))
    await waitUntil(timeout: 2) { sut.status == .disconnected }
    #expect(sut.status == .disconnected)
    #expect(channel.status == .subscribed)

    let start = ContinuousClock.now
    await sut.removeChannel(channel)
    let elapsed = ContinuousClock.now - start
    #expect(
      elapsed < .seconds(1.5),
      "removeChannel on a dead socket stalled waiting for phx_close (\(elapsed))"
    )
    #expect(channel.status == .unsubscribed)

    // Reconnect: the new connection must not receive a stale phx_leave from
    // the send buffer.
    await sut.connect()
    #expect(sut.status == .connected)
    try? await Task.sleep(nanoseconds: 200_000_000)

    let leaves = sockets.value[1].sentMessages.filter { $0.event == "phx_leave" }
    #expect(leaves.isEmpty, "Stale phx_leave was flushed into the new connection")
  }
}
