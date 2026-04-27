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
          server.onEvent = { @Sendable [weak server] event in
            guard let msg = event.realtimeMessage else { return }
            if msg.event == "heartbeat" {
              server?.send(
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
              server?.send(
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
          // Retain the server so `client.other` (a weak ref) stays valid.
          servers?.withValue { $0.append(server) }
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
      // Simulate the OS tearing down the socket while backgrounded (not a user-initiated
      // disconnect). Closing the server side triggers a .close event on the client without
      // going through disconnect(), so wasConnectedBeforeBackground remains set.
      servers.value.last?.close(code: nil, reason: "OS teardown")
      _ = await sut.statusChange.first { $0 == .disconnected }
      XCTAssertEqual(sut.status, .disconnected)

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
      // Simulate the OS tearing down the socket while backgrounded.
      servers.value.last?.close(code: nil, reason: "OS teardown")
      _ = await sut.statusChange.first { $0 == .disconnected }
      XCTAssertEqual(sut.status, .disconnected)

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
