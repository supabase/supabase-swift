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
@testable import RealtimeV2

#if os(Linux)
  // RealtimeLifecycleTests are disabled on Linux due to timing flakiness.
#else

  @Suite
  struct RealtimeLifecycleTests {
    let url = URL(string: "http://localhost:54321/realtime/v1")!
    let apiKey = "publishable.api.key"

    let http: HTTPClientMock
    let testClock: TestClock<Duration>
    let servers: LockIsolated<[FakeWebSocket]>

    init() {
      http = HTTPClientMock()
      testClock = TestClock()
      servers = LockIsolated([])
    }

    private func makeClient(handleAppLifecycle: Bool = false) -> RealtimeClientV2 {
      RealtimeClientV2(
        url: url,
        options: RealtimeClientOptions(
          headers: ["apikey": apiKey],
          accessToken: { "custom.access.token" },
          handleAppLifecycle: handleAppLifecycle
        ),
        wsTransport: { [servers] _, _ in
          let (client, server) = FakeWebSocket.fakes()
          // Auto-respond to heartbeats and phx_join so subscribe() completes.
          // Retain the server so `client.other` (a weak ref) stays valid.
          servers.withValue { $0.append(server) }
          Task { [server] in
            for await event in server.events {
              guard let msg = event.realtimeMessage else { continue }
              if msg.event == "heartbeat" {
                server.send(
                  RealtimeMessageV2(
                    joinRef: msg.joinRef,
                    ref: msg.ref,
                    topic: "phoenix",
                    event: "phx_reply",
                    payload: ["response": [:]]
                  )
                )
              } else if msg.event == "phx_join" {
                // Mirror the incoming ref so the client's pending push resolves,
                // regardless of reconnect cycles (ref counter resets on disconnect).
                server.send(
                  RealtimeMessageV2(
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
        http: http,
        clock: testClock
      )
    }

    @Test
    func handleAppForegroundWhileConnectedIsNoOp() async throws {
      let sut = makeClient()
      let channel = sut.channel("public:messages")
      try await channel.subscribeWithError()

      let statusBefore = sut.status
      let channelStatusBefore = channel.status

      sut.handleAppBackground()
      await sut.handleAppForeground()

      #expect(sut.status == statusBefore)
      #expect(channel.status == channelStatusBefore)
    }

    @Test
    func handleAppForegroundWithoutPriorBackgroundIsNoOp() async {
      let sut = makeClient()
      #expect(sut.status == .disconnected)

      await sut.handleAppForeground()
      #expect(sut.status == .disconnected)
    }

    @Test
    func handleAppForegroundDoesNotConnectIfNotConnectedBeforeBackground() async {
      let sut = makeClient()
      #expect(sut.status == .disconnected)

      sut.handleAppBackground()
      await sut.handleAppForeground()
      #expect(sut.status == .disconnected)
    }

    @Test
    func handleAppForegroundReconnectsWhenBackgroundedWhileConnected() async throws {
      let sut = makeClient()
      await sut.connect()
      #expect(sut.status == .connected)

      sut.handleAppBackground()
      // Subscribe before the OS close so the buffered .disconnected event is
      // not missed even when .reconnecting follows immediately (PR #1015 made
      // handleClose call initiateReconnect).
      let statusUpdates = sut.statusChange
      servers.value.last?.close(code: nil, reason: "OS teardown")
      // Status sequence: .connected → .disconnected → .connecting (reconnecting).
      _ = await statusUpdates.first { $0 == .disconnected }

      // Advance the test clock past the 7-second reconnect delay so the
      // auto-reconnect task wakes and performConnection() runs.
      await testClock.advance(by: .seconds(8))
      _ = await statusUpdates.first { $0 == .connected }
      #expect(sut.status == .connected)

      // handleAppForeground is a no-op: the auto-reconnect already recovered
      // the connection and the state observer will rejoin channels.
      await sut.handleAppForeground()
      #expect(sut.status == .connected)
    }

    @Test
    func handleAppForegroundResubscribesChannelsWhenBackgroundedWhileConnected() async throws {
      let sut = makeClient()
      let channel = sut.channel("public:messages")
      try await channel.subscribeWithError()
      #expect(sut.status == .connected)
      #expect(channel.status == .subscribed)

      sut.handleAppBackground()
      let statusUpdates = sut.statusChange
      servers.value.last?.close(code: nil, reason: "OS teardown")
      _ = await statusUpdates.first { $0 == .disconnected }

      await testClock.advance(by: .seconds(8))
      _ = await statusUpdates.first { $0 == .connected }
      #expect(sut.status == .connected)

      // rejoinChannels() is launched as a fire-and-forget Task from the state
      // observer's handleConnected(isReconnect: true) path. Poll until it
      // completes (FakeWebSocket delivers phx_reply synchronously but the task
      // needs scheduler turns to run).
      await waitUntil(timeout: 5) { channel.status == .subscribed }
      #expect(channel.status == .subscribed)

      // handleAppForeground is a no-op: already reconnected with channel resubscribed.
      await sut.handleAppForeground()
      #expect(sut.status == .connected)
      #expect(channel.status == .subscribed)
    }

    @Test
    func rejoinChannelsSubscribesConcurrently() async throws {
      let connectionCount = LockIsolated(0)
      let rejoinJoinTopics = LockIsolated<Set<String>>([])

      let sut = RealtimeClientV2(
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
                  RealtimeMessageV2(
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
                    RealtimeMessageV2(
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
                  rejoinJoinTopics.withValue { $0.insert(msg.topic) }
                }
              }
            }
          }
          return client
        },
        http: http,
        clock: testClock
      )

      let channelA = sut.channel("topic-a")
      let channelB = sut.channel("topic-b")
      try await channelA.subscribeWithError()
      try await channelB.subscribeWithError()
      #expect(channelA.status == .subscribed)
      #expect(channelB.status == .subscribed)

      let statusUpdates = sut.statusChange
      servers.value.last?.close(code: nil, reason: "OS teardown")
      _ = await statusUpdates.first { $0 == .disconnected }

      await testClock.advance(by: .seconds(8))
      _ = await statusUpdates.first { $0 == .connected }

      await waitUntil(timeout: 5) { rejoinJoinTopics.value.count == 2 }

      #expect(rejoinJoinTopics.value == ["realtime:topic-a", "realtime:topic-b"])

      sut.disconnect()
    }

    @Test
    func explicitDisconnectWhileBackgroundedDoesNotReconnectOnForeground() async throws {
      let sut = makeClient()
      await sut.connect()
      #expect(sut.status == .connected)

      sut.handleAppBackground()
      // Explicit developer disconnect (e.g. sign-out) must clear the lifecycle flag so
      // handleAppForeground() does not silently undo it.
      sut.disconnect()
      #expect(sut.status == .disconnected)

      await sut.handleAppForeground()
      #expect(sut.status == .disconnected)
    }

    @Test
    func heartbeatTaskDoesNotRetainClient() async throws {
      final class WeakBox: @unchecked Sendable {
        weak var client: RealtimeClientV2?
      }
      let box = WeakBox()

      func scope() async {
        let sut = makeClient()
        box.client = sut
        await sut.connect()
        #expect(sut.status == .connected)

        await testClock.advance(by: .seconds(30))

        servers.value.last?.close(code: 4001, reason: "test teardown")
      }
      await scope()

      await waitUntil(timeout: 5) { box.client == nil }

      #expect(
        box.client == nil,
        "RealtimeClientV2 leaked: the heartbeat task retained self, preventing deinit."
      )
    }

    @Test
    func deinitClosesLiveWebSocketConnection() async throws {
      final class WeakBox: @unchecked Sendable {
        weak var client: RealtimeClientV2?
      }
      let box = WeakBox()

      func scope() async {
        let sut = makeClient()
        box.client = sut
        await sut.connect()
        #expect(sut.status == .connected)
        // Deliberately no `disconnect()` — dropping a connected client must still tear
        // down the socket.
      }
      await scope()

      // The fake pair is cross-linked, so the server peer flips to closed only when the
      // client-side socket is actually closed (not merely deallocated).
      let server = try #require(servers.value.last)
      await waitUntil(timeout: 5) { box.client == nil && server.isClosed }

      #expect(
        box.client == nil,
        "RealtimeClientV2 leaked: a task retained self while connected, preventing deinit."
      )
      #expect(
        server.isClosed,
        "WebSocket was left open after the connected client was deallocated."
      )
    }

    @Test
    func connectionManagerDeinitClosesLiveWebSocketConnection() async throws {
      let (client, server) = FakeWebSocket.fakes()

      func scope() async throws {
        let sut = ConnectionManager(
          transport: { _, _ in client },
          url: URL(string: "ws://localhost")!,
          headers: [:],
          reconnectDelay: 0.1,
          logger: supabaseDefaultLogger(label: "io.supabase.realtime"),
          clock: testClock
        )
        try await sut.connect()
        #expect(client.isClosed == false)
      }
      try await scope()

      await waitUntil(timeout: 5) { server.isClosed }

      #expect(
        server.isClosed,
        "WebSocket was left open after the connected ConnectionManager was deallocated."
      )
    }

    @Test
    func handleAppLifecycleFalseDoesNotInstallLifecycleManager() {
      let sut = makeClient(handleAppLifecycle: false)
      #expect(sut.mutableState.lifecycleManager == nil)
    }

    #if os(iOS) || os(tvOS) || os(visionOS) || os(macOS)
      @Test
      func handleAppLifecycleTrueInstallsLifecycleManager() {
        let sut = makeClient(handleAppLifecycle: true)
        #expect(sut.mutableState.lifecycleManager != nil)
        _ = sut
      }
    #endif
  }

#endif
