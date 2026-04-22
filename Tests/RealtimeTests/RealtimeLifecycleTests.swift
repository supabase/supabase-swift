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

#if canImport(UIKit)
  import UIKit
#elseif canImport(AppKit)
  import AppKit
#endif

#if os(Linux)
  @available(
    *, unavailable, message: "RealtimeLifecycleTests are disabled on Linux due to timing flakiness"
  )
  final class RealtimeLifecycleTests: XCTestCase {}
#else

  @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
  final class RealtimeLifecycleTests: XCTestCase {
    let url = URL(string: "http://localhost:54321/realtime/v1")!
    let apiKey = "anon.api.key"

    #if !os(Windows) && !os(Linux) && !os(Android)
      override func invokeTest() {
        withMainSerialExecutor {
          super.invokeTest()
        }
      }
    #endif

    var http: HTTPClientMock!
    var testClock: TestClock<Duration>!
    /// Holds the currently active fake server so tests can drive it.
    var currentServer: LockIsolated<FakeWebSocket?>!

    override func setUp() {
      super.setUp()
      http = HTTPClientMock()
      testClock = TestClock()
      _clock = testClock
      currentServer = LockIsolated(nil)
    }

    private func makeClient(handleAppLifecycle: Bool = false) -> RealtimeClientV2 {
      let currentServer = self.currentServer!
      return RealtimeClientV2(
        url: url,
        options: RealtimeClientOptions(
          headers: ["apikey": apiKey],
          handleAppLifecycle: handleAppLifecycle,
          accessToken: { "custom.access.token" }
        ),
        wsTransport: { _, _ in
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
              server?.send(.messagesSubscribed)
            }
          }
          currentServer.setValue(server)
          return client
        },
        http: http
      )
    }

    func testSetAppStateActiveFalseDisconnects() async {
      let sut = makeClient()
      await sut.connect()
      XCTAssertEqual(sut.status, .connected)

      await sut.setAppStateActive(false)
      XCTAssertEqual(sut.status, .disconnected)
    }

    func testSetAppStateActiveTrueConnects() async {
      let sut = makeClient()
      XCTAssertEqual(sut.status, .disconnected)

      await sut.setAppStateActive(true)
      XCTAssertEqual(sut.status, .connected)
    }

    func testSetAppStateActiveTrueResubscribesChannels() async throws {
      let sut = makeClient()
      let channel = sut.channel("public:messages")

      try await channel.subscribeWithError()
      XCTAssertEqual(channel.status, .subscribed)

      // Background: disconnect
      await sut.setAppStateActive(false)
      XCTAssertEqual(sut.status, .disconnected)

      // Foreground: connect and rejoin channels
      await sut.setAppStateActive(true)
      XCTAssertEqual(sut.status, .connected)
      XCTAssertEqual(channel.status, .subscribed)
    }

    func testHandleAppLifecycleFalseDoesNotInstallLifecycleManager() {
      let sut = makeClient(handleAppLifecycle: false)
      XCTAssertNil(sut.mutableState.lifecycleManager)
    }

    #if os(iOS) || os(tvOS) || os(visionOS) || os(macOS)
      func testHandleAppLifecycleTrueInstallsLifecycleManager() {
        let sut = makeClient(handleAppLifecycle: true)
        XCTAssertNotNil(sut.mutableState.lifecycleManager)
        // Keep a reference alive until assertion runs.
        _ = sut
      }

      func testBackgroundNotificationDisconnects() async throws {
        let sut = makeClient(handleAppLifecycle: true)
        await sut.connect()
        XCTAssertEqual(sut.status, .connected)

        #if canImport(UIKit)
          NotificationCenter.default.post(
            name: UIApplication.didEnterBackgroundNotification, object: nil
          )
        #elseif canImport(AppKit)
          NotificationCenter.default.post(
            name: NSApplication.willResignActiveNotification, object: nil
          )
        #endif

        // Poll briefly for the async task dispatched by the observer to complete.
        try await waitFor(timeout: 1.0) { sut.status == .disconnected }
        XCTAssertEqual(sut.status, .disconnected)
      }

      func testForegroundNotificationReconnects() async throws {
        let sut = makeClient(handleAppLifecycle: true)
        await sut.connect()
        XCTAssertEqual(sut.status, .connected)

        #if canImport(UIKit)
          NotificationCenter.default.post(
            name: UIApplication.didEnterBackgroundNotification, object: nil
          )
        #elseif canImport(AppKit)
          NotificationCenter.default.post(
            name: NSApplication.willResignActiveNotification, object: nil
          )
        #endif
        try await waitFor(timeout: 1.0) { sut.status == .disconnected }

        #if canImport(UIKit)
          NotificationCenter.default.post(
            name: UIApplication.willEnterForegroundNotification, object: nil
          )
        #elseif canImport(AppKit)
          NotificationCenter.default.post(
            name: NSApplication.willBecomeActiveNotification, object: nil
          )
        #endif
        try await waitFor(timeout: 1.0) { sut.status == .connected }
        XCTAssertEqual(sut.status, .connected)
      }
    #endif

    private func waitFor(
      timeout: TimeInterval,
      condition: @escaping @Sendable () -> Bool
    ) async throws {
      let deadline = Date().addingTimeInterval(timeout)
      while Date() < deadline {
        if condition() { return }
        try await Task.sleep(nanoseconds: 10_000_000)  // 10ms
      }
      if !condition() {
        XCTFail("Condition not met within \(timeout)s")
      }
    }
  }

#endif
