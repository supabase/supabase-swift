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
      http: HTTPClientMock(),
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

  /// A removal whose `phx_leave` is in flight when the socket drops must end with the removal.
  /// The reconnect's rejoin used to reset the channel being removed and subscribe it again: its
  /// `phx_join` reached the new socket (with no `join_ref` once the removal cleared it), and the
  /// server's `phx_close` for that stray join, sent when the topic's next channel joined, closed
  /// and unmapped the next channel.
  @Test
  func removalSpanningReconnectDoesNotRejoinTheRemovedChannel() async throws {
    let sockets = LockIsolated<[AsyncFakeWebSocket]>([])

    let sut = RealtimeClientV2(
      url: url,
      options: RealtimeClientOptions(
        headers: ["apikey": apiKey],
        heartbeatInterval: 10,
        reconnectDelay: 0.05,
        timeoutInterval: 1,
        accessToken: { "token" },
        handleAppLifecycle: false
      ),
      wsTransport: { _, _ in
        let socket = AsyncFakeWebSocket()
        // The first socket dies before it answers the removal's `phx_leave`.
        socket.serverResponder = AsyncFakeWebSocket.phoenixResponder(
          answersLeave: !sockets.value.isEmpty
        )
        sockets.withValue { $0.append(socket) }
        return socket
      },
      http: HTTPClientMock(),
      clock: ContinuousClock()
    )
    defer { sut.disconnect() }

    // Another channel keeps the client connected once the topic's channel is removed.
    let other = sut.channel("other")
    try await other.subscribeWithError()
    let removed = sut.channel("room")
    try await removed.subscribeWithError()

    let removal = Task { await sut.removeChannel(removed) }
    await waitUntil(timeout: 2) {
      sockets.value[0].sentMessages.contains {
        $0.event == "phx_leave" && $0.topic == removed.topic
      }
    }
    sockets.value[0].receiveFromServer(.close(code: 1006, reason: "network lost"))
    await removal.value

    // The reconnect rejoins the other channel on the new socket.
    let rejoined = await waitUntil(timeout: 5) {
      sockets.value.count == 2 && other.status == .subscribed
        && sockets.value[1].sentMessages.contains {
          $0.event == "phx_join" && $0.topic == other.topic
        }
    }
    try #require(rejoined, "The other channel did not rejoin after the reconnect")
    try? await Task.sleep(nanoseconds: 300_000_000)

    let newSocket = sockets.value[1]
    let strayJoins = newSocket.sentMessages.filter {
      $0.event == "phx_join" && $0.topic == removed.topic
    }
    #expect(strayJoins.isEmpty, "The reconnect rejoined the channel being removed: \(strayJoins)")
    #expect(removed.status == .unsubscribed)
    #expect(sut.channels[removed.topic] == nil)

    // The app joins the topic again; the channel must survive the server's handling of any
    // earlier join of the topic on this socket, and any retry of it.
    let next = sut.channel("room")
    #expect(next !== removed)
    do {
      try await next.subscribeWithError()
    } catch {
      Issue.record("The topic's next channel failed to subscribe: \(error)")
    }
    try? await Task.sleep(nanoseconds: 1_500_000_000)

    #expect(next.status == .subscribed)
    #expect(sut.channels[next.topic] === next, "The topic's next channel was unmapped")
    let joins = newSocket.sentMessages.filter { $0.event == "phx_join" }
    #expect(joins.allSatisfy { $0.joinRef != nil }, "A phx_join went out without a join_ref")
  }

  /// `removeChannel(_:)` stops a join still in flight. Unmapped, the channel
  /// would never see its reply and would keep retrying the join, and the
  /// server closes the topic's next channel on each duplicate join.
  @Test
  func removeChannelStopsAJoinInFlight() async throws {
    let sockets = LockIsolated<[AsyncFakeWebSocket]>([])

    let sut = RealtimeClientV2(
      url: url,
      options: RealtimeClientOptions(
        headers: ["apikey": apiKey],
        heartbeatInterval: 10,
        reconnectDelay: 0.05,
        timeoutInterval: 1,
        accessToken: { "token" },
        handleAppLifecycle: false
      ),
      wsTransport: { _, _ in
        let socket = AsyncFakeWebSocket()
        let phoenix = AsyncFakeWebSocket.phoenixResponder(answersLeave: true)
        // The server never answers the first join of the topic.
        let answeredRoomJoin = LockIsolated(false)
        socket.serverResponder = { message, socket in
          if message.event == "phx_join", message.topic == "realtime:room",
            !answeredRoomJoin.value
          {
            answeredRoomJoin.setValue(true)
            return
          }
          phoenix(message, socket)
        }
        sockets.withValue { $0.append(socket) }
        return socket
      },
      http: HTTPClientMock(),
      clock: ContinuousClock()
    )
    defer { sut.disconnect() }

    // Another channel keeps the client connected once the topic's channel is removed.
    let other = sut.channel("other")
    try await other.subscribeWithError()
    let removed = sut.channel("room")
    let subscription = Task { try await removed.subscribeWithError() }
    await waitUntil(timeout: 2) {
      sockets.value[0].sentMessages.contains {
        $0.event == "phx_join" && $0.topic == removed.topic
      }
    }

    await sut.removeChannel(removed)
    #expect(removed.status == .unsubscribed)
    #expect(sut.channels[removed.topic] == nil)

    // Past the attempt's timeout and the first retry delay.
    try? await Task.sleep(nanoseconds: 2_500_000_000)
    let joins = sockets.value[0].sentMessages.filter {
      $0.event == "phx_join" && $0.topic == removed.topic
    }
    #expect(joins.count == 1, "The removed channel retried its join: \(joins)")

    subscription.cancel()
    _ = try? await subscription.value
  }

  /// `removeChannel(_:)` marks the channel removed even when it is already
  /// `.unsubscribed`, e.g. after its subscribe gave up during an outage. A
  /// reconnect that captured the channel before the removal must not join it
  /// once it is unmapped.
  @Test
  func removedChannelDoesNotRejoinAfterItsSubscribeGaveUp() async throws {
    let sockets = LockIsolated<[AsyncFakeWebSocket]>([])

    let sut = RealtimeClientV2(
      url: url,
      options: RealtimeClientOptions(
        headers: ["apikey": apiKey],
        heartbeatInterval: 10,
        reconnectDelay: 0.05,
        timeoutInterval: 0.3,
        maxRetryAttempts: 1,
        accessToken: { "token" },
        handleAppLifecycle: false
      ),
      wsTransport: { _, _ in
        let socket = AsyncFakeWebSocket()
        let phoenix = AsyncFakeWebSocket.phoenixResponder(answersLeave: true)
        // The server never answers a join of the topic.
        socket.serverResponder = { message, socket in
          if message.event == "phx_join", message.topic == "realtime:room" { return }
          phoenix(message, socket)
        }
        sockets.withValue { $0.append(socket) }
        return socket
      },
      http: HTTPClientMock(),
      clock: ContinuousClock()
    )
    defer { sut.disconnect() }

    // Another channel keeps the client connected once the topic's channel is removed.
    let other = sut.channel("other")
    try await other.subscribeWithError()
    let removed = sut.channel("room")
    await #expect(throws: (any Error).self) { try await removed.subscribeWithError() }
    #expect(removed.status == .unsubscribed)

    await sut.removeChannel(removed)
    // The step of a reconnect's `rejoinChannels()` that captured the channel before the removal.
    try? await removed.rejoinAfterReconnect()

    let joins = sockets.value[0].sentMessages.filter {
      $0.event == "phx_join" && $0.topic == removed.topic
    }
    #expect(joins.count == 1, "The removed channel joined again: \(joins)")
  }

  /// A channel the server closed is unmapped, so it never joins again:
  /// neither through a reconnect's rejoin nor through a later subscribe.
  @Test
  func channelClosedByTheServerNeverJoinsAgain() async throws {
    let sockets = LockIsolated<[AsyncFakeWebSocket]>([])

    let sut = RealtimeClientV2(
      url: url,
      options: RealtimeClientOptions(
        headers: ["apikey": apiKey],
        heartbeatInterval: 10,
        reconnectDelay: 0.05,
        timeoutInterval: 0.3,
        maxRetryAttempts: 1,
        accessToken: { "token" },
        handleAppLifecycle: false
      ),
      wsTransport: { _, _ in
        let socket = AsyncFakeWebSocket()
        socket.serverResponder = AsyncFakeWebSocket.phoenixResponder(answersLeave: true)
        sockets.withValue { $0.append(socket) }
        return socket
      },
      http: HTTPClientMock(),
      clock: ContinuousClock()
    )
    defer { sut.disconnect() }

    let channel = sut.channel("room")
    try await channel.subscribeWithError()
    let join = try #require(
      sockets.value[0].sentMessages.last { $0.event == "phx_join" && $0.topic == channel.topic }
    )
    sockets.value[0].reply(
      RealtimeMessageV2(
        joinRef: join.joinRef, ref: join.joinRef, topic: channel.topic, event: "phx_close",
        payload: [:]
      )
    )
    #expect(await waitUntil(timeout: 2) { sut.channels[channel.topic] == nil })

    try? await channel.rejoinAfterReconnect()
    await #expect(throws: CancellationError.self) { try await channel.subscribeWithError() }

    #expect(channel.status == .unsubscribed)
    let joins = sockets.value[0].sentMessages.filter {
      $0.event == "phx_join" && $0.topic == channel.topic
    }
    #expect(joins.count == 1, "The closed channel joined again: \(joins)")
  }
}


extension AsyncFakeWebSocket {
  /// A Phoenix-like server for one socket: it acks heartbeats and confirms joins, answers
  /// `phx_leave` (when `answersLeave`) with a reply and the channel's `phx_close`, and closes the
  /// earlier join of a topic when a second join of that topic arrives on the same socket, with a
  /// `phx_close` carrying the earlier join's `join_ref` (Phoenix's duplicate-join rule).
  static func phoenixResponder(answersLeave: Bool)
    -> @Sendable (RealtimeMessageV2, AsyncFakeWebSocket) -> Void
  {
    let joins = LockIsolated<[String: String?]>([:])
    return { message, socket in
      switch message.event {
      case "heartbeat":
        socket.reply(
          RealtimeMessageV2(
            joinRef: nil, ref: message.ref, topic: "phoenix", event: "phx_reply",
            payload: ["response": [:], "status": "ok"]
          )
        )
      case "phx_join":
        let previous = joins.withValue { joins -> String?? in
          defer { joins[message.topic] = .some(message.joinRef) }
          return joins[message.topic]
        }
        if let previous {
          socket.reply(
            RealtimeMessageV2(
              joinRef: previous, ref: previous, topic: message.topic, event: "phx_close",
              payload: [:]
            )
          )
        }
        socket.reply(
          RealtimeMessageV2(
            joinRef: message.joinRef, ref: message.ref, topic: message.topic, event: "phx_reply",
            payload: ["response": ["postgres_changes": []], "status": "ok"]
          )
        )
      case "phx_leave":
        guard answersLeave else { return }
        joins.withValue { _ = $0.removeValue(forKey: message.topic) }
        socket.reply(
          RealtimeMessageV2(
            joinRef: message.joinRef, ref: message.ref, topic: message.topic, event: "phx_reply",
            payload: ["response": [:], "status": "ok"]
          )
        )
        socket.reply(
          RealtimeMessageV2(
            joinRef: message.joinRef, ref: message.joinRef, topic: message.topic,
            event: "phx_close", payload: [:]
          )
        )
      default:
        break
      }
    }
  }
}
