import ConcurrencyExtras
import Foundation
import TestHelpers
import Testing

@testable import Realtime

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

  private func makeOptions(
    timeout: Duration = .seconds(3),
    maxRetryAttempts: Int = RealtimeClientOptions.defaultMaxRetryAttempts
  ) -> RealtimeClientOptions {
    RealtimeClientOptions(
      headers: ["apikey": apiKey],
      // Long heartbeat so heartbeat machinery can't interfere.
      heartbeatInterval: .seconds(10),
      reconnectDelay: .milliseconds(50),
      timeout: timeout,
      maxRetryAttempts: maxRetryAttempts,
      accessToken: { "token" }
    )
  }

  /// Defect 1 in #1145: `sawReconnecting` was cleared only on `.connected`.
  /// When the single auto-reconnect attempt failed (network still down), the
  /// latch stayed armed, and the next successful `connect()` — e.g. from a
  /// channel's `connectOnSubscribe` — was misclassified as a reconnect
  /// completion. The resulting `rejoinChannels()` reset cancelled the very
  /// join that connect was performing, surfacing as `CancellationError`.
  ///
  /// Issue #1147 closed the underlying window this defect needed: auto-reconnect
  /// used to be single-shot, so a failed attempt parked the client in
  /// `.disconnected` and needed an external trigger (like the workaround this
  /// test used to exercise) to recover — that's exactly the state where the
  /// stale latch could bite. Now `ConnectionManager` keeps retrying with
  /// backoff and never surfaces `.disconnected` mid-retry, so recovery (and
  /// the resulting `rejoinChannels()`) happens automatically.
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
        // Attempt 2 is the first automatic reconnect — the network is still
        // down. Attempt 3, a later automatic retry, succeeds once it recovers.
        if attempt == 2 {
          throw RealtimeError.transport("network down")
        }
        let socket = AsyncFakeWebSocket()
        socket.serverResponder = AsyncFakeWebSocket.realtimeServerResponder()
        sockets.withValue { $0.append(socket) }
        return socket
      },
      http: HTTPClient(transport: RecordingTransport()),
      clock: ContinuousClock()
    )
    defer { sut.disconnect() }

    let channel = sut.channel("room-1")
    try await channel.subscribeWithError()
    #expect(channel.status == .subscribed)

    // Outage: the socket errors out and the first auto-reconnect attempt fails.
    sockets.value[0].receiveFromServer(.text("not a valid frame"))

    // No external trigger (no new channel, no manual `connect()`): the client
    // must retry on its own until the network recovers, then rejoin the
    // existing channel automatically.
    let recovered = await waitUntil(timeout: 5) {
      connectAttempts.value >= 3 && sut.status == .connected && channel.status == .subscribed
    }
    #expect(recovered, "Client did not recover automatically after a failed auto-reconnect attempt")
  }

  /// Issue #1584: a `connect()` call made during an outage waited on the automatic reconnect,
  /// which keeps retrying until the network is back, and its caller could not cancel it. Once
  /// cancelled, it must return right away, and must not report `.disconnected` while that
  /// reconnect is still running.
  @Test
  func cancelledConnectReturnsDuringFailedAutoReconnect() async throws {
    let sockets = LockIsolated<[AsyncFakeWebSocket]>([])
    let connectAttempts = LockIsolated(0)
    let networkDown = LockIsolated(false)

    let sut = RealtimeClientV2(
      url: url,
      options: makeOptions(),
      wsTransport: { _, _ in
        connectAttempts.withValue { $0 += 1 }
        if networkDown.value {
          throw RealtimeError.transport("network down")
        }
        let socket = AsyncFakeWebSocket()
        socket.serverResponder = AsyncFakeWebSocket.realtimeServerResponder()
        sockets.withValue { $0.append(socket) }
        return socket
      },
      http: HTTPClient(transport: RecordingTransport()),
      clock: ContinuousClock()
    )
    defer { sut.disconnect() }

    await sut.connect()
    #expect(sut.status == .connected)

    // Outage: the socket errors out, and every automatic reconnect fails until the network is
    // back.
    networkDown.setValue(true)
    sockets.value[0].receiveFromServer(.text("not a valid frame"))
    let reconnecting = await waitUntil(timeout: 2) {
      connectAttempts.value >= 2 && sut.status == .connecting
    }
    #expect(reconnecting)

    let connectReturned = LockIsolated(false)
    let caller = Task {
      await sut.connect()
      connectReturned.setValue(true)
    }
    try await Task.sleep(nanoseconds: 50_000_000)
    caller.cancel()

    let returned = await waitUntil(timeout: 1) { connectReturned.value }
    #expect(returned, "A cancelled connect() should return while the reconnect keeps failing")
    #expect(sut.status == .connecting, "The reconnect is still running")

    // The reconnect the caller gave up on still recovers the client once the network is back.
    networkDown.setValue(false)
    let recovered = await waitUntil(timeout: 5) { sut.status == .connected }
    #expect(recovered)
  }

  /// Issue #1584, knock-on: `subscribeWithError()` bounds each attempt with `withTimeout`, whose
  /// task group cannot return before the attempt does. The attempt was stuck in `connect()`,
  /// which ignored the cancellation, so subscribing during an outage hung for the whole outage
  /// instead of failing after `maxRetryAttempts` attempts.
  @Test
  func subscribeGivesUpAfterRetriesDuringFailedAutoReconnect() async throws {
    let sockets = LockIsolated<[AsyncFakeWebSocket]>([])
    let connectAttempts = LockIsolated(0)
    let networkDown = LockIsolated(false)

    let sut = RealtimeClientV2(
      url: url,
      options: makeOptions(timeout: .milliseconds(200), maxRetryAttempts: 2),
      wsTransport: { _, _ in
        connectAttempts.withValue { $0 += 1 }
        if networkDown.value {
          throw RealtimeError.transport("network down")
        }
        let socket = AsyncFakeWebSocket()
        socket.serverResponder = AsyncFakeWebSocket.realtimeServerResponder()
        sockets.withValue { $0.append(socket) }
        return socket
      },
      http: HTTPClient(transport: RecordingTransport()),
      clock: ContinuousClock()
    )
    defer { sut.disconnect() }

    await sut.connect()

    // Outage: the socket errors out, and every automatic reconnect fails for the rest of the test.
    networkDown.setValue(true)
    sockets.value[0].receiveFromServer(.text("not a valid frame"))
    let reconnecting = await waitUntil(timeout: 2) {
      connectAttempts.value >= 2 && sut.status == .connecting
    }
    #expect(reconnecting)

    let channel = sut.channel("room-outage")
    let subscribeFinished = LockIsolated(false)
    let subscribeError = LockIsolated<(any Error)?>(nil)
    let subscriber = Task {
      do {
        try await channel.subscribeWithError()
      } catch {
        subscribeError.setValue(error)
      }
      subscribeFinished.setValue(true)
    }

    // Two 200 ms attempts, with a retry delay of about a second between them.
    let finished = await waitUntil(timeout: 5) { subscribeFinished.value }
    #expect(finished, "subscribeWithError() should give up after its retries instead of hanging")
    #expect((subscribeError.value as? RealtimeError)?.kind == .maxRetryAttemptsReached)
    subscriber.cancel()
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
      http: HTTPClient(transport: RecordingTransport()),
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

  /// Issue #1148 (follow-up to #1145 defect 3): `phx_error` was routed by
  /// topic only, like `phx_close`. An error belonging to a stale join must
  /// not kill the current subscription; a ref-less error still must.
  @Test
  func stalePhxErrorDoesNotKillCurrentSubscription() async throws {
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
      http: HTTPClient(transport: RecordingTransport()),
      clock: ContinuousClock()
    )
    defer { sut.disconnect() }

    let channel = sut.channel("room-error")
    try await channel.subscribeWithError()
    #expect(channel.status == .subscribed)

    // A phx_error for a *different* join_ref (a stale incarnation) arrives.
    let socket = sockets.value[0]
    socket.reply(
      RealtimeMessageV2(
        joinRef: "stale-join-ref",
        ref: nil,
        topic: channel.topic,
        event: "phx_error",
        payload: [:]
      )
    )

    try? await Task.sleep(nanoseconds: 300_000_000)
    #expect(channel.status == .subscribed, "Stale phx_error killed the current subscription")

    // A phx_error without a join_ref (e.g. an auth error) still applies.
    socket.reply(
      RealtimeMessageV2(
        joinRef: nil,
        ref: nil,
        topic: channel.topic,
        event: "phx_error",
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
      options: makeOptions(timeout: .seconds(3)),
      wsTransport: { _, _ in
        let socket = AsyncFakeWebSocket()
        socket.serverResponder = AsyncFakeWebSocket.realtimeServerResponder()
        sockets.withValue { $0.append(socket) }
        return socket
      },
      http: HTTPClient(transport: RecordingTransport()),
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
