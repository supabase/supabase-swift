//
//  RealtimeLifecycleTests.swift
//  RealtimeTests
//
//  Created by Guilherme Souza on 22/04/26.
//

import Clocks
import ConcurrencyExtras
import Foundation
import Logging
import TestHelpers
import Testing

@testable import Realtime

@Suite
struct RealtimeLifecycleTests {
  let url = URL(string: "http://localhost:54321/realtime/v1")!
  let apiKey = "publishable.api.key"

  let http: RecordingTransport
  let testClock: SignalingTestClock
  let servers: LockIsolated<[FakeWebSocket]>
  /// Whether the fake server answers heartbeats. Off, the socket is dead the way a suspended
  /// app leaves it: open, and silent.
  let answersHeartbeats: LockIsolated<Bool>

  init() {
    http = RecordingTransport()
    testClock = SignalingTestClock()
    servers = LockIsolated([])
    answersHeartbeats = LockIsolated(true)
  }

  private func makeClient(
    handleAppLifecycle: Bool = false, monitorsNetworkPath: Bool = false,
    reconnectBackoff: BackoffPolicy? = nil
  ) -> RealtimeClient {
    RealtimeClient(
      url: url,
      options: RealtimeClientOptions(
        headers: ["apikey": apiKey],
        accessToken: { "custom.access.token" },
        handleAppLifecycle: handleAppLifecycle,
        monitorsNetworkPath: monitorsNetworkPath
      ),
      wsTransport: { [servers, answersHeartbeats] _, _ in
        let (client, server) = FakeWebSocket.fakes()
        servers.withValue { $0.append(server) }
        Task { [server] in
          for await event in server.events {
            guard let msg = event.realtimeMessage else { continue }
            if msg.event == "heartbeat" {
              guard answersHeartbeats.value else { continue }
              server.send(
                RealtimeMessage(
                  joinRef: msg.joinRef,
                  ref: msg.ref,
                  topic: "phoenix",
                  event: "phx_reply",
                  payload: ["response": [:]]
                )
              )
            } else if msg.event == "phx_join" {
              server.send(
                RealtimeMessage(
                  joinRef: msg.joinRef,
                  ref: msg.ref,
                  topic: msg.topic,
                  event: "phx_reply",
                  payload: [
                    "response": [
                      "postgres_changes": []
                    ],
                    "status": "ok",
                  ]
                )
              )
            }
          }
        }
        return client
      },
      http: HTTPClient(transport: http),
      clock: testClock,
      reconnectBackoff: reconnectBackoff ?? RealtimeClient.defaultReconnectBackoff
    )
  }

  @Test
  func handleAppForegroundWhileConnectedKeepsTheConnection() async throws {
    let sut = makeClient()
    let channel = await sut.channel("public:messages")
    try await channel.subscribe()

    #expect(await sut.status == .connected)
    #expect(await channel.status == .subscribed)

    await sut.handleAppBackground()
    await sut.handleAppForeground()

    #expect(await sut.status == .connected)
    #expect(await channel.status == .subscribed)
  }

  /// A suspended app leaves the socket open and silent, and `status` still says connected. The
  /// foreground probe finds out after its 5 s deadline, not after the 25 s heartbeat interval.
  @Test
  func foregroundProbeOnADeadSocketReconnectsBeforeTheHeartbeatInterval() async throws {
    let sut = makeClient()
    try await sut.connect()
    #expect(servers.value.count == 1)
    answersHeartbeats.setValue(false)
    let statusUpdates = await sut.statusChanges()
    let start = testClock.now

    await sut.handleAppForeground()
    await testClock.advance(by: .seconds(5))

    _ = await statusUpdates.first { $0 == .connecting }
    _ = await statusUpdates.first { $0 == .connected }
    #expect(servers.value.count == 2)
    #expect(start.duration(to: testClock.now) == .seconds(5))
  }

  @Test
  func foregroundProbeOnALiveSocketKeepsTheConnection() async throws {
    let sut = makeClient()
    try await sut.connect()
    let heartbeats = await sut.heartbeats()

    await sut.handleAppForeground()
    _ = await heartbeats.first { if case .acknowledged = $0 { true } else { false } }
    await testClock.advance(by: .seconds(5))
    await sut.flushInbox()

    #expect(await sut.status == .connected)
    #expect(servers.value.count == 1)
  }

  /// The network is back while the client sleeps out a 30 s backoff: the wake retries at once.
  @Test
  func wakeCutsABackoffShort() async throws {
    let sut = makeClient(reconnectBackoff: .steps([.seconds(30)]))
    try await sut.connect()
    await testClock.advance(by: .seconds(3))
    let statusUpdates = await sut.statusChanges()
    servers.value.last?.close(code: nil, reason: "network change")
    _ = await statusUpdates.first { $0 == .reconnecting }
    let start = testClock.now

    sut.inbox.yield(.wake)
    _ = await statusUpdates.first { $0 == .connected }

    #expect(servers.value.count == 2)
    #expect(testClock.now == start)
  }

  /// A path that flaps right after an attempt started cannot start another at once: the wake
  /// retries when 2 s have passed since that attempt, long before the 30 s backoff ends.
  @Test
  func wakeJustAfterAnAttemptWaitsForTheCooldown() async throws {
    let sut = makeClient(reconnectBackoff: .steps([.seconds(30)]))
    try await sut.connect()
    let statusUpdates = await sut.statusChanges()
    servers.value.last?.close(code: nil, reason: "network change")
    _ = await statusUpdates.first { $0 == .reconnecting }
    let start = testClock.now

    sut.inbox.yield(.wake)
    sut.inbox.yield(.wake)
    await sut.flushInbox()
    #expect(servers.value.count == 1)
    #expect(await sut.status == .reconnecting)

    await testClock.advance(by: .seconds(2))
    _ = await statusUpdates.first { $0 == .connected }

    #expect(servers.value.count == 2)
    #expect(start.duration(to: testClock.now) == .seconds(2))
  }

  @Test
  func handleAppForegroundWithoutPriorBackgroundIsNoOp() async {
    let sut = makeClient()
    #expect(await sut.status == .disconnected)

    await sut.handleAppForeground()
    #expect(await sut.status == .disconnected)
  }

  @Test
  func handleAppForegroundDoesNotConnectIfNotConnectedBeforeBackground() async {
    let sut = makeClient()
    #expect(await sut.status == .disconnected)

    await sut.handleAppBackground()
    await sut.handleAppForeground()
    #expect(await sut.status == .disconnected)
  }

  @Test
  func handleAppForegroundReconnectsWhenBackgroundedWhileConnected() async throws {
    let sut = makeClient()
    try await sut.connect()
    #expect(await sut.status == .connected)

    await sut.handleAppBackground()
    // Open the stream before the OS close so no transition is missed.
    let statusUpdates = await sut.statusChanges()
    servers.value.last?.close(code: nil, reason: "OS teardown")
    // The client waits out the backoff in `.reconnecting`, not `.disconnected`.
    _ = await statusUpdates.first { $0 == .reconnecting }

    // auto-reconnect task wakes and reconnects.
    await testClock.advance(by: .seconds(8))
    _ = await statusUpdates.first { $0 == .connected }
    #expect(await sut.status == .connected)

    // the connection and rejoins channels itself.
    await sut.handleAppForeground()
    #expect(await sut.status == .connected)
  }

  @Test
  func handleAppForegroundResubscribesChannelsWhenBackgroundedWhileConnected() async throws {
    let sut = makeClient()
    let channel = await sut.channel("public:messages")
    try await channel.subscribe()
    #expect(await sut.status == .connected)
    #expect(await channel.status == .subscribed)

    await sut.handleAppBackground()
    let statusUpdates = await sut.statusChanges()
    let channelUpdates = await channel.statusChanges()
    servers.value.last?.close(code: nil, reason: "OS teardown")
    // The client waits out the backoff in `.reconnecting`, not `.disconnected`.
    _ = await statusUpdates.first { $0 == .reconnecting }

    await testClock.advance(by: .seconds(8))
    _ = await statusUpdates.first { $0 == .connected }
    #expect(await sut.status == .connected)

    // rejoinChannels() runs after the reconnect: it resets the channel and joins again on
    // the new socket. Wait for that new join to complete rather than for a `.subscribed`
    // that the stale pre-reconnect state could still satisfy.
    _ = await channelUpdates.first { $0 == .subscribing }
    _ = await channelUpdates.first { $0 == .subscribed }
    #expect(await channel.status == .subscribed)

    await sut.handleAppForeground()
    #expect(await sut.status == .connected)
    #expect(await channel.status == .subscribed)
  }

  @Test
  func rejoinChannelsSubscribesConcurrently() async throws {
    let connectionCount = LockIsolated(0)
    let rejoinJoinTopics = LockIsolated<Set<String>>([])

    let sut = RealtimeClient(
      url: url,
      options: RealtimeClientOptions(
        headers: ["apikey": apiKey],
        accessToken: { "custom.access.token" }
      ),
      wsTransport: { [servers, connectionCount, rejoinJoinTopics] _, _ in
        let (client, server) = FakeWebSocket.fakes()
        servers.withValue { $0.append(server) }
        let isFirstConnection = connectionCount.withValue { count -> Bool in
          count += 1
          return count == 1
        }
        Task { [server] in
          for await event in server.events {
            guard let msg = event.realtimeMessage else { continue }
            if msg.event == "heartbeat" {
              server.send(
                RealtimeMessage(
                  joinRef: msg.joinRef,
                  ref: msg.ref,
                  topic: "phoenix",
                  event: "phx_reply",
                  payload: ["response": [:]]
                )
              )
            } else if msg.event == "phx_join" {
              if isFirstConnection {
                server.send(
                  RealtimeMessage(
                    joinRef: msg.joinRef,
                    ref: msg.ref,
                    topic: msg.topic,
                    event: "phx_reply",
                    payload: [
                      "response": ["postgres_changes": []],
                      "status": "ok",
                    ]
                  )
                )
              } else {
                rejoinJoinTopics.withValue { _ = $0.insert(msg.topic) }
              }
            }
          }
        }
        return client
      },
      http: HTTPClient(transport: http),
      clock: testClock
    )

    let channelA = await sut.channel("topic-a")
    let channelB = await sut.channel("topic-b")
    try await channelA.subscribe()
    try await channelB.subscribe()
    #expect(await channelA.status == .subscribed)
    #expect(await channelB.status == .subscribed)

    let statusUpdates = await sut.statusChanges()
    servers.value.last?.close(code: nil, reason: "OS teardown")
    // The client waits out the backoff in `.reconnecting`, not `.disconnected`.
    _ = await statusUpdates.first { $0 == .reconnecting }

    await testClock.advance(by: .seconds(8))
    _ = await statusUpdates.first { $0 == .connected }

    await waitUntil(timeout: 5) { rejoinJoinTopics.value.count == 2 }

    #expect(rejoinJoinTopics.value == ["realtime:topic-a", "realtime:topic-b"])

    await sut.disconnect()
  }

  @Test
  func explicitDisconnectWhileBackgroundedDoesNotReconnectOnForeground() async throws {
    let sut = makeClient()
    try await sut.connect()
    #expect(await sut.status == .connected)

    await sut.handleAppBackground()
    await sut.disconnect()
    #expect(await sut.status == .disconnected)

    await sut.handleAppForeground()
    #expect(await sut.status == .disconnected)
  }

  @Test
  func heartbeatTaskDoesNotRetainClient() async throws {
    final class WeakBox: @unchecked Sendable {
      weak var client: RealtimeClient?
    }
    let box = WeakBox()

    func scope() async throws {
      let sut = makeClient()
      box.client = sut
      try await sut.connect()
      #expect(await sut.status == .connected)

      await testClock.advance(by: .seconds(30))

      servers.value.last?.close(code: 4001, reason: "test teardown")
    }
    try await scope()

    await waitUntil(timeout: 5) { box.client == nil }

    #expect(
      box.client == nil,
      "RealtimeClient leaked: the heartbeat task retained self, preventing deinit."
    )
  }

  @Test
  func deinitClosesLiveWebSocketConnection() async throws {
    final class WeakBox: @unchecked Sendable {
      weak var client: RealtimeClient?
    }
    let box = WeakBox()

    func scope() async throws {
      let sut = makeClient()
      box.client = sut
      try await sut.connect()
      #expect(await sut.status == .connected)
    }
    try await scope()

    let server = try #require(servers.value.last)
    await waitUntil(timeout: 5) { box.client == nil && server.isClosed }

    #expect(
      box.client == nil,
      "RealtimeClient leaked: a task retained self while connected, preventing deinit."
    )
    #expect(
      server.isClosed,
      "WebSocket was left open after the connected client was deallocated."
    )
  }

  @Test
  func releasingTheClientAndItsChannelsClosesTheSocket() async throws {
    final class WeakBox: @unchecked Sendable {
      weak var client: RealtimeClient?
      weak var subscribed: RealtimeChannel?
      weak var idle: RealtimeChannel?
    }
    let box = WeakBox()

    func scope() async throws {
      let sut = makeClient()
      box.client = sut
      try await sut.connect()
      let subscribed = await sut.channel("subscribed")
      try await subscribed.subscribe()
      box.subscribed = subscribed
      box.idle = await sut.channel("idle")
    }
    try await scope()

    let server = try #require(servers.value.last)
    await waitUntil(timeout: 5) {
      box.client == nil && box.subscribed == nil && box.idle == nil && server.isClosed
    }

    #expect(box.client == nil, "RealtimeClient leaked while it still had channels.")
    #expect(box.subscribed == nil && box.idle == nil, "A channel outlived its client.")
    #expect(server.isClosed, "WebSocket was left open after the client was released.")
  }

  @Test
  func handleAppLifecycleFalseDoesNotInstallLifecycleObserver() async {
    let sut = makeClient(handleAppLifecycle: false)
    #expect(await !sut.hasLifecycleObserver)
  }

  #if os(iOS) || os(tvOS) || os(visionOS) || os(macOS)
    @Test
    func handleAppLifecycleTrueInstallsLifecycleObserver() async {
      let sut = makeClient(handleAppLifecycle: true)
      #expect(await sut.hasLifecycleObserver)
      _ = sut
    }
  #endif

  @Test
  func monitorsNetworkPathFalseDoesNotInstallNetworkPathObserver() async {
    let sut = makeClient(monitorsNetworkPath: false)
    #expect(await !sut.hasNetworkPathObserver)
  }

  #if canImport(Network)
    @Test
    func monitorsNetworkPathTrueInstallsNetworkPathObserver() async {
      let sut = makeClient(monitorsNetworkPath: true)
      #expect(await sut.hasNetworkPathObserver)
      _ = sut
    }
  #endif
}

extension RealtimeClient {
  /// Whether the client observes the app lifecycle.
  fileprivate var hasLifecycleObserver: Bool {
    #if os(iOS) || os(tvOS) || os(visionOS) || os(macOS)
      lifecycleObserver != nil
    #else
      false
    #endif
  }

  /// Whether the client watches the network path.
  fileprivate var hasNetworkPathObserver: Bool {
    #if canImport(Network)
      networkPathObserver != nil
    #else
      false
    #endif
  }
}
