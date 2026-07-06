//
//  RealtimeLifecycleTests.swift
//  RealtimeTests
//
//  Created by Guilherme Souza on 22/04/26.
//

import Clocks
import ConcurrencyExtras
import Foundation
import TestHelpers
import XCTest

@testable import Realtime
@testable import RealtimeV2

#if os(Linux)
  @available(
    *, unavailable, message: "RealtimeLifecycleTests are disabled on Linux due to timing flakiness"
  )
  final class RealtimeLifecycleTests: XCTestCase {}
#else

  @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
  final class RealtimeLifecycleTests: XCTestCase {
    let url = URL(string: "http://localhost:54321/realtime/v1")!
    let apiKey = "publishable.api.key"

    var http: HTTPClientMock!
    var testClock: TestClock<Duration>!
    var servers: LockIsolated<[FakeWebSocket]>!

    override func setUp() {
      super.setUp()
      http = HTTPClientMock()
      testClock = TestClock()
      _clock = testClock
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
          servers?.withValue { $0.append(server) }
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
        http: http
      )
    }

    func testHandleAppForegroundWhileConnectedIsNoOp() async throws {
      let sut = makeClient()
      let channel = sut.channel("public:messages")
      try await channel.subscribeWithError()

      let statusBefore = sut.status
      let channelStatusBefore = channel.status

      sut.handleAppBackground()
      await sut.handleAppForeground()

      XCTAssertEqual(sut.status, statusBefore)
      XCTAssertEqual(channel.status, channelStatusBefore)
    }

    func testHandleAppForegroundWithoutPriorBackgroundIsNoOp() async {
      let sut = makeClient()
      XCTAssertEqual(sut.status, .disconnected)

      await sut.handleAppForeground()
      XCTAssertEqual(sut.status, .disconnected)
    }

    func testHandleAppForegroundDoesNotConnectIfNotConnectedBeforeBackground() async {
      let sut = makeClient()
      XCTAssertEqual(sut.status, .disconnected)

      sut.handleAppBackground()
      await sut.handleAppForeground()
      XCTAssertEqual(sut.status, .disconnected)
    }

    func testHandleAppForegroundReconnectsWhenBackgroundedWhileConnected() async throws {
      let sut = makeClient()
      await sut.connect()
      XCTAssertEqual(sut.status, .connected)

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
      XCTAssertEqual(sut.status, .connected)

      // handleAppForeground is a no-op: the auto-reconnect already recovered
      // the connection and the state observer will rejoin channels.
      await sut.handleAppForeground()
      XCTAssertEqual(sut.status, .connected)
    }

    func testHandleAppForegroundResubscribesChannelsWhenBackgroundedWhileConnected() async throws {
      let sut = makeClient()
      let channel = sut.channel("public:messages")
      try await channel.subscribeWithError()
      XCTAssertEqual(sut.status, .connected)
      XCTAssertEqual(channel.status, .subscribed)

      sut.handleAppBackground()
      let statusUpdates = sut.statusChange
      servers.value.last?.close(code: nil, reason: "OS teardown")
      _ = await statusUpdates.first { $0 == .disconnected }

      await testClock.advance(by: .seconds(8))
      _ = await statusUpdates.first { $0 == .connected }
      XCTAssertEqual(sut.status, .connected)

      // rejoinChannels() is launched as a fire-and-forget Task from the state
      // observer's handleConnected(isReconnect: true) path. Poll until it
      // completes (FakeWebSocket delivers phx_reply synchronously but the task
      // needs scheduler turns to run).
      let deadline = Date().addingTimeInterval(5)
      while channel.status != .subscribed, Date() < deadline {
        try? await Task.sleep(nanoseconds: 10_000_000)  // 10 ms
      }
      XCTAssertEqual(channel.status, .subscribed)

      // handleAppForeground is a no-op: already reconnected with channel resubscribed.
      await sut.handleAppForeground()
      XCTAssertEqual(sut.status, .connected)
      XCTAssertEqual(channel.status, .subscribed)
    }

    func testExplicitDisconnectWhileBackgroundedDoesNotReconnectOnForeground() async throws {
      let sut = makeClient()
      await sut.connect()
      XCTAssertEqual(sut.status, .connected)

      sut.handleAppBackground()
      // Explicit developer disconnect (e.g. sign-out) must clear the lifecycle flag so
      // handleAppForeground() does not silently undo it.
      sut.disconnect()
      XCTAssertEqual(sut.status, .disconnected)

      await sut.handleAppForeground()
      XCTAssertEqual(sut.status, .disconnected)
    }

    func testHeartbeatTaskDoesNotRetainClient() async throws {
      weak var weakClient: RealtimeClientV2?

      func scope() async {
        let sut = makeClient()
        weakClient = sut
        await sut.connect()
        XCTAssertEqual(sut.status, .connected)

        await testClock.advance(by: .seconds(30))

        servers.value.last?.close(code: 4001, reason: "test teardown")
      }
      await scope()

      let deadline = Date().addingTimeInterval(5)
      while weakClient != nil, Date() < deadline {
        await Task.yield()
        try? await Task.sleep(nanoseconds: 10_000_000)
      }

      XCTAssertNil(
        weakClient,
        "RealtimeClientV2 leaked: the heartbeat task retained self, preventing deinit."
      )
    }

    func testHandleAppLifecycleFalseDoesNotInstallLifecycleManager() {
      let sut = makeClient(handleAppLifecycle: false)
      XCTAssertNil(sut.mutableState.lifecycleManager)
    }

    #if os(iOS) || os(tvOS) || os(visionOS) || os(macOS)
      func testHandleAppLifecycleTrueInstallsLifecycleManager() {
        let sut = makeClient(handleAppLifecycle: true)
        XCTAssertNotNil(sut.mutableState.lifecycleManager)
        _ = sut
      }
    #endif
  }

#endif
