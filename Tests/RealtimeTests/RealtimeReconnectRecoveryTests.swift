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

    sockets.value[0].receiveFromServer(.text("not a valid frame"))

    let recovered = await waitUntil(timeout: 5) {
      connectAttempts.value >= 3 && sut.status == .connected && channel.status == .subscribed
    }
    #expect(recovered, "Client did not recover automatically after a failed auto-reconnect attempt")
  }

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
    #expect(channel.status == .subscribed, "Stale phx_close killed the current subscription")
    #expect(sut.channels[channel.topic] != nil, "Stale phx_close removed the channel")

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

    await sut.connect()
    #expect(sut.status == .connected)
    try? await Task.sleep(nanoseconds: 200_000_000)

    let leaves = sockets.value[1].sentMessages.filter { $0.event == "phx_leave" }
    #expect(leaves.isEmpty, "Stale phx_leave was flushed into the new connection")
  }
}
