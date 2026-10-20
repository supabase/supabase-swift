import ConcurrencyExtras
import Foundation
import TestHelpers
import Testing

@testable import Realtime

@Suite
struct RealtimeReconnectRecoveryTests {
  let url = URL(string: "http://localhost:54321/realtime/v1")!
  let apiKey = "anon.api.key"

  private func makeOptions(timeout: Duration = .seconds(3)) -> RealtimeClientOptions {
    RealtimeClientOptions(
      headers: ["apikey": apiKey],
      heartbeatInterval: .seconds(10),
      reconnectDelay: .milliseconds(50),
      timeout: timeout,
      accessToken: { "token" }
    )
  }

  /// stale latch could bite. Now `RealtimeClient` keeps retrying with
  @Test
  func subscribeConvergesAfterFailedAutoReconnect() async throws {
    let sockets = LockIsolated<[AsyncFakeWebSocket]>([])
    let connectAttempts = LockIsolated(0)

    let sut = RealtimeClient(
      url: url,
      options: makeOptions(),
      wsTransport: { _, _ in
        let attempt = connectAttempts.withValue { count -> Int in
          count += 1
          return count
        }
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

    let channel = await sut.channel("room-1")
    try await channel.subscribe()
    #expect(await channel.status == .subscribed)

    // Outage: the socket drops and the first auto-reconnect attempt fails. A remote close with a
    // transport-level code triggers the reconnect; `RealtimeClient` now only logs a malformed
    // frame, so it can no longer stand in for the outage.
    sockets.value[0].receiveFromServer(.close(code: 1006, reason: "network down"))

    let recovered = await waitUntil(timeout: 5) {
      let clientStatus = await sut.status
      let channelStatus = await channel.status
      return connectAttempts.value >= 3 && clientStatus == .connected
        && channelStatus == .subscribed
    }
    #expect(recovered, "Client did not recover automatically after a failed auto-reconnect attempt")

    await sut.disconnect()
  }

  @Test
  func stalePhxCloseDoesNotKillCurrentSubscription() async throws {
    let sockets = LockIsolated<[AsyncFakeWebSocket]>([])

    let sut = RealtimeClient(
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

    let channel = await sut.channel("room-close")
    try await channel.subscribe()
    #expect(await channel.status == .subscribed)

    let socket = sockets.value[0]
    let joinRef = socket.sentMessages.first { $0.event == "phx_join" }?.ref
    #expect(joinRef != nil)

    socket.reply(
      RealtimeMessageV2(
        joinRef: "stale-join-ref",
        ref: nil,
        topic: channel.topic,
        event: "phx_close",
        payload: [:]
      )
    )

    try? await Task.sleep(nanoseconds: 300_000_000)
    #expect(await channel.status == .subscribed, "Stale phx_close killed the current subscription")
    #expect(await sut.channels[channel.topic] != nil, "Stale phx_close removed the channel")

    socket.reply(
      RealtimeMessageV2(
        joinRef: joinRef,
        ref: nil,
        topic: channel.topic,
        event: "phx_close",
        payload: [:]
      )
    )
    await waitUntil(timeout: 2) { await channel.status == .unsubscribed }
    #expect(await channel.status == .unsubscribed)

    await sut.disconnect()
  }

  @Test
  func stalePhxErrorDoesNotKillCurrentSubscription() async throws {
    let sockets = LockIsolated<[AsyncFakeWebSocket]>([])

    let sut = RealtimeClient(
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

    let channel = await sut.channel("room-error")
    try await channel.subscribe()
    #expect(await channel.status == .subscribed)

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
    #expect(await channel.status == .subscribed, "Stale phx_error killed the current subscription")

    socket.reply(
      RealtimeMessageV2(
        joinRef: nil,
        ref: nil,
        topic: channel.topic,
        event: "phx_error",
        payload: [:]
      )
    )
    await waitUntil(timeout: 2) { await channel.status == .unsubscribed }
    #expect(await channel.status == .unsubscribed)

    await sut.disconnect()
  }

  @Test
  func unsubscribeOnDeadSocketSkipsLeaveAndDoesNotStall() async throws {
    let sockets = LockIsolated<[AsyncFakeWebSocket]>([])

    let sut = RealtimeClient(
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

    let channel = await sut.channel("room-leave")
    try await channel.subscribe()
    #expect(await channel.status == .subscribed)

    sockets.value[0].receiveFromServer(.close(code: 4001, reason: "auth"))
    await waitUntil(timeout: 2) { await sut.status == .disconnected }
    #expect(await sut.status == .disconnected)
    #expect(await channel.status == .subscribed)

    let start = ContinuousClock.now
    await sut.removeChannel(channel)
    let elapsed = ContinuousClock.now - start
    #expect(
      elapsed < .seconds(1.5),
      "removeChannel on a dead socket stalled waiting for phx_close (\(elapsed))"
    )
    #expect(await channel.status == .unsubscribed)

    try await sut.connect()
    #expect(await sut.status == .connected)
    try? await Task.sleep(nanoseconds: 200_000_000)

    let leaves = sockets.value[1].sentMessages.filter { $0.event == "phx_leave" }
    #expect(leaves.isEmpty, "Stale phx_leave was flushed into the new connection")

    await sut.disconnect()
  }

  /// A removal whose `phx_leave` is in flight when the socket drops ends with the removal. The
  /// reconnect's rejoin used to reset the channel being removed and subscribe it again: its
  /// `phx_join` reached the new socket after the client had forgotten the channel, so the server
  /// closed the topic's next channel when the stray join was retried.
  @Test
  func removalSpanningReconnectDoesNotRejoinTheRemovedChannel() async throws {
    let sockets = LockIsolated<[AsyncFakeWebSocket]>([])

    let sut = RealtimeClient(
      url: url,
      options: RealtimeClientOptions(
        headers: ["apikey": apiKey],
        heartbeatInterval: .seconds(10),
        reconnectDelay: .milliseconds(50),
        timeout: .seconds(1),
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
      http: HTTPClient(transport: RecordingTransport()),
      clock: ContinuousClock()
    )

    // Another channel keeps the client connected once the topic's channel is removed.
    let other = await sut.channel("other")
    try await other.subscribe()
    let removed = await sut.channel("room")
    try await removed.subscribe()

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
      guard sockets.value.count == 2, await other.status == .subscribed else { return false }
      return sockets.value[1].sentMessages.contains {
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
    #expect(await removed.status == .unsubscribed)
    #expect(await sut.channels[removed.topic] == nil)

    // The app joins the topic again; the channel must survive the server's handling of any
    // earlier join of the topic on this socket, and any retry of it.
    let next = await sut.channel("room")
    #expect(next !== removed)
    do {
      try await next.subscribe()
    } catch {
      Issue.record("The topic's next channel failed to subscribe: \(error)")
    }
    try? await Task.sleep(nanoseconds: 1_500_000_000)

    #expect(await next.status == .subscribed)
    #expect(await sut.channels[next.topic] === next, "The topic's next channel was unmapped")
    let joins = newSocket.sentMessages.filter { $0.event == "phx_join" }
    #expect(joins.allSatisfy { $0.joinRef != nil }, "A phx_join went out without a join_ref")

    await sut.disconnect()
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
