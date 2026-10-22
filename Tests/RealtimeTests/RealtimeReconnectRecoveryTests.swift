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
}
