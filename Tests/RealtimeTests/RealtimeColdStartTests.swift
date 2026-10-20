import ConcurrencyExtras
import Foundation
import TestHelpers
import Testing

@testable import Realtime

@Suite
struct RealtimeColdStartTests {
  let url = URL(string: "http://localhost:54321/realtime/v1")!
  let apiKey = "anon.api.key"

  private func makeClient(socket: AsyncFakeWebSocket) -> RealtimeClient {
    RealtimeClient(
      url: url,
      options: RealtimeClientOptions(
        headers: ["apikey": apiKey],
        heartbeatInterval: .seconds(10),
        reconnectDelay: .milliseconds(100),
        timeout: .seconds(2),
        accessToken: { "token" }
      ),
      wsTransport: { _, _ in
        try await Task.sleep(nanoseconds: 20_000_000)
        return socket
      },
      http: HTTPClient(transport: RecordingTransport()),
      clock: ContinuousClock()
    )
  }

  /// streams consumed in detached tasks, then `subscribe()`.
  @Test
  func coldStartSubscribe_realTimingProfile() async throws {
    for iteration in 1...5 {
      let socket = AsyncFakeWebSocket()
      socket.serverResponder = AsyncFakeWebSocket.realtimeServerResponder()

      let sut = makeClient(socket: socket)

      let channel = await sut.channel("library-realtime")
      let libros = await channel.postgresChanges(AnyAction.self, schema: "library", table: "libros")
      let files = await channel.postgresChanges(
        AnyAction.self, schema: "library", table: "libro_files")

      let t1 = Task { for await _ in libros {} }
      let t2 = Task { for await _ in files {} }
      defer {
        t1.cancel()
        t2.cancel()
      }

      do {
        try await channel.subscribe()
      } catch {
        Issue.record("Iteration \(iteration): subscribe failed: \(error)")
        return
      }

      #expect(await channel.status == .subscribed, "Iteration \(iteration)")
      await sut.disconnect()
    }
  }

  /// `ensureSocketConnected` → concurrent `connect()` → the client's
  @Test
  func coldStartConcurrentSubscribes_doNotGoDeaf() async throws {
    for iteration in 1...5 {
      let socket = AsyncFakeWebSocket()
      socket.serverResponder = AsyncFakeWebSocket.realtimeServerResponder()

      let sut = makeClient(socket: socket)

      let channel1 = await sut.channel("room-1")
      let channel2 = await sut.channel("room-2")

      async let s1: Void = channel1.subscribe()
      async let s2: Void = channel2.subscribe()

      do {
        _ = try await (s1, s2)
      } catch {
        Issue.record("Iteration \(iteration): subscribe failed: \(error)")
        return
      }

      #expect(await channel1.status == .subscribed, "Iteration \(iteration)")
      #expect(await channel2.status == .subscribed, "Iteration \(iteration)")
      await sut.disconnect()
    }
  }

  /// `subscribe()` was a no-op for `.subscribed` channels,
  @Test
  func channelsRejoinAfterReconnect() async throws {
    let sockets = LockIsolated<[AsyncFakeWebSocket]>([])

    let sut = RealtimeClient(
      url: url,
      options: RealtimeClientOptions(
        headers: ["apikey": apiKey],
        heartbeatInterval: .seconds(10),
        reconnectDelay: .milliseconds(50),
        timeout: .seconds(5),
        accessToken: { "token" }
      ),
      wsTransport: { _, _ in
        let socket = AsyncFakeWebSocket()
        socket.serverResponder = AsyncFakeWebSocket.realtimeServerResponder()
        sockets.withValue { $0.append(socket) }
        return socket
      },
      http: HTTPClient(transport: RecordingTransport()),
      clock: ContinuousClock()
    )

    let channel = await sut.channel("room-rejoin")

    try await channel.subscribe()
    #expect(await channel.status == .subscribed)
    #expect(sockets.value.count == 1)

    // A remote close with a transport-level code initiates a reconnect. A malformed
    // frame used to do the same, but `RealtimeClient` now only logs undecodable frames.
    // Application-level codes (4000–4999) skip reconnect by design (auth errors should
    // not loop with the same token).
    sockets.value[0].receiveFromServer(.close(code: 1006, reason: "abnormal closure"))
    let reconnected = await waitUntil(timeout: 5) { sockets.value.count >= 2 }
    guard reconnected else {
      Issue.record("No reconnect within 5 s")
      return
    }

    await waitUntil(timeout: 5) {
      let channelStatus = await channel.status
      return sockets.value[1].sentMessages.contains { $0.event == "phx_join" }
        && channelStatus == .subscribed
    }
    #expect(await channel.status == .subscribed, "Channel did not rejoin after reconnect")

    let joinsSentOnNewSocket = sockets.value[1].sentMessages.filter { $0.event == "phx_join" }
    #expect(joinsSentOnNewSocket.count == 1, "Expected one phx_join on the new socket")

    await sut.disconnect()
  }

  /// remote close or by the heartbeat timer itself), we verify that after
  @Test
  func pendingHeartbeatDoesNotLeakAcrossReconnect() async throws {
    let sockets = LockIsolated<[AsyncFakeWebSocket]>([])

    let sut = RealtimeClient(
      url: url,
      options: RealtimeClientOptions(
        headers: ["apikey": apiKey],
        heartbeatInterval: .milliseconds(200),
        reconnectDelay: .milliseconds(50),
        timeout: .seconds(5),
        accessToken: { "token" }
      ),
      wsTransport: { _, _ in
        let socket = AsyncFakeWebSocket()
        if sockets.value.count >= 1 {
          socket.serverResponder = AsyncFakeWebSocket.realtimeServerResponder()
        }
        sockets.withValue { $0.append(socket) }
        return socket
      },
      http: HTTPClient(transport: RecordingTransport()),
      clock: ContinuousClock()
    )

    let heartbeatStatuses = LockIsolated<[HeartbeatStatus]>([])
    let heartbeats = await sut.heartbeats()
    let heartbeatTask = Task {
      for await status in heartbeats {
        heartbeatStatuses.withValue { $0.append(status) }
      }
    }
    defer { heartbeatTask.cancel() }

    try await sut.connect()

    // never acks). The reconnect may be triggered by either the remote close
    await waitUntil { heartbeatStatuses.value.contains(.sent) }

    // A remote close with a transport-level code initiates a reconnect. (A malformed
    // frame used to do the same; `RealtimeClient` now only logs undecodable frames.)
    sockets.value[0].receiveFromServer(.close(code: 1006, reason: "abnormal closure"))

    let reconnected = await waitUntil(timeout: 5) { sockets.value.count >= 2 }
    guard reconnected else {
      Issue.record("No reconnect within 5 s — socket count: \(sockets.value.count)")
      return
    }

    let countAfterFirstReconnect = sockets.value.count
    await waitUntil(timeout: 0.2 * 5 + 1.0) {
      sockets.value.count > countAfterFirstReconnect
    }

    #expect(
      sockets.value.count == countAfterFirstReconnect,
      """
      Perpetual reconnects detected — pendingHeartbeatRef likely leaked \
      into the replacement connection: \(heartbeatStatuses.value)
      """
    )

    await sut.disconnect()
  }
}

final class AsyncFakeWebSocket: WebSocket, @unchecked Sendable {
  struct MutableState {
    var isClosed: Bool = false
    var sentMessages: [RealtimeMessageV2] = []
    var closeCode: Int?
    var closeReason: String?
  }

  let mutableState = LockIsolated(MutableState())
  let deliveryQueue = DispatchQueue(label: "AsyncFakeWebSocket.delivery")
  let events: AsyncStream<LegacyWebSocketEvent>
  private let eventsContinuation: AsyncStream<LegacyWebSocketEvent>.Continuation

  init() {
    (events, eventsContinuation) = AsyncStream.makeStream()
  }

  var serverResponder: (@Sendable (RealtimeMessageV2, AsyncFakeWebSocket) -> Void)?

  var closeCode: Int? { mutableState.value.closeCode }
  var closeReason: String? { mutableState.value.closeReason }
  var isClosed: Bool { mutableState.value.isClosed }
  let `protocol`: String = ""

  var sentMessages: [RealtimeMessageV2] { mutableState.value.sentMessages }

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
    deliveryQueue.async { [weak self] in
      self?.receiveFromServer(.close(code: code ?? 1005, reason: reason ?? ""))
    }
  }

  func receiveFromServer(_ event: LegacyWebSocketEvent) {
    mutableState.withValue {
      if case .close(let code, let reason) = event {
        $0.isClosed = true
        $0.closeCode = code
        $0.closeReason = reason
      }
    }
    eventsContinuation.yield(event)
    if case .close = event {
      eventsContinuation.finish()
    }
  }

  func reply(_ message: RealtimeMessageV2) {
    let serializer = RealtimeSerializer()
    let text = try! serializer.encodeText(message)
    receiveFromServer(.text(text))
  }
}
