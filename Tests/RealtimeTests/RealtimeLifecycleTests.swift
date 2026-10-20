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

#if os(Linux)
#else

  @Suite
  struct RealtimeLifecycleTests {
    let url = URL(string: "http://localhost:54321/realtime/v1")!
    let apiKey = "publishable.api.key"

    let http: RecordingTransport
    let testClock: SignalingTestClock
    let servers: LockIsolated<[FakeWebSocket]>

    init() {
      http = RecordingTransport()
      testClock = SignalingTestClock()
      servers = LockIsolated([])
    }

    private func makeClient(handleAppLifecycle: Bool = false) -> RealtimeClient {
      RealtimeClient(
        url: url,
        options: RealtimeClientOptions(
          headers: ["apikey": apiKey],
          accessToken: { "custom.access.token" },
          handleAppLifecycle: handleAppLifecycle
        ),
        wsTransport: { [servers] _, _ in
          let (client, server) = FakeWebSocket.fakes()
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
        http: HTTPClient(transport: http),
        clock: testClock
      )
    }

    @Test
    func handleAppForegroundWhileConnectedIsNoOp() async throws {
      let sut = makeClient()
      let channel = await sut.channel("public:messages")
      try await channel.subscribe()

      let statusBefore = await sut.status
      let channelStatusBefore = await channel.status

      await sut.handleAppBackground()
      await sut.handleAppForeground()

      #expect(await sut.status == statusBefore)
      #expect(await channel.status == channelStatusBefore)
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
      // Status sequence: .connected → .connecting (reconnecting). `RealtimeClient` no longer
      // publishes an intermediate `.disconnected` when it starts reconnecting.
      _ = await statusUpdates.first { $0 == .connecting }

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
      // `RealtimeClient` goes straight to `.connecting` while it reconnects; there is no
      // intermediate `.disconnected` any more.
      _ = await statusUpdates.first { $0 == .connecting }

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
      // No intermediate `.disconnected`: the client goes straight to `.connecting`.
      _ = await statusUpdates.first { $0 == .connecting }

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
    func handleAppLifecycleFalseDoesNotInstallLifecycleManager() {
      let sut = makeClient(handleAppLifecycle: false)
      #expect(sut.lifecycleManager == nil)
    }

    #if os(iOS) || os(tvOS) || os(visionOS) || os(macOS)
      @Test
      func handleAppLifecycleTrueInstallsLifecycleManager() {
        let sut = makeClient(handleAppLifecycle: true)
        #expect(sut.lifecycleManager != nil)
        _ = sut
      }
    #endif
  }

#endif
