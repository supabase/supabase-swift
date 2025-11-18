//
//  ConnectionStateMachineTests.swift
//  Realtime Tests
//
//  Created on 17/01/25.
//

import Foundation
import XCTest

@testable import Realtime

final class ConnectionStateMachineTests: XCTestCase {
  var stateMachine: ConnectionStateMachine!
  var mockWebSocket: FakeWebSocket!
  var connectCallCount = 0
  var lastConnectURL: URL?
  var lastConnectHeaders: [String: String]?

  override func setUp() async throws {
    try await super.setUp()
    connectCallCount = 0
    lastConnectURL = nil
    lastConnectHeaders = nil
    (mockWebSocket, _) = FakeWebSocket.fakes()
  }

  override func tearDown() async throws {
    stateMachine = nil
    mockWebSocket = nil
    try await super.tearDown()
  }

  // MARK: - Helper

  func makeStateMachine(
    url: URL = URL(string: "ws://localhost")!,
    headers: [String: String] = [:],
    reconnectDelay: TimeInterval = 0.1
  ) -> ConnectionStateMachine {
    ConnectionStateMachine(
      transport: { [weak self] url, headers in
        self?.connectCallCount += 1
        self?.lastConnectURL = url
        self?.lastConnectHeaders = headers
        return self!.mockWebSocket
      },
      url: url,
      headers: headers,
      reconnectDelay: reconnectDelay,
      logger: nil
    )
  }

  // MARK: - Tests

  func testInitialStateIsDisconnected() async {
    stateMachine = makeStateMachine()

    let connection = await stateMachine.connection
    let isConnected = await stateMachine.isConnected

    XCTAssertNil(connection)
    XCTAssertFalse(isConnected)
  }

  func testConnectSuccessfully() async throws {
    stateMachine = makeStateMachine(
      url: URL(string: "ws://example.com")!,
      headers: ["Authorization": "Bearer token"]
    )

    let connection = try await stateMachine.connect()

    XCTAssertNotNil(connection)
    XCTAssertEqual(connectCallCount, 1)
    XCTAssertEqual(lastConnectURL?.absoluteString, "ws://example.com")
    XCTAssertEqual(lastConnectHeaders?["Authorization"], "Bearer token")

    let isConnected = await stateMachine.isConnected
    XCTAssertTrue(isConnected)
  }

  func testMultipleConnectCallsReuseConnection() async throws {
    stateMachine = makeStateMachine()

    let connection1 = try await stateMachine.connect()
    let connection2 = try await stateMachine.connect()
    let connection3 = try await stateMachine.connect()

    XCTAssertEqual(connectCallCount, 1, "Should only connect once")
    XCTAssertTrue(connection1 === mockWebSocket)
    XCTAssertTrue(connection2 === mockWebSocket)
    XCTAssertTrue(connection3 === mockWebSocket)
  }

  func testConcurrentConnectCallsCreateSingleConnection() async throws {
    stateMachine = makeStateMachine()

    // Simulate concurrent connect calls
    async let connection1 = stateMachine.connect()
    async let connection2 = stateMachine.connect()
    async let connection3 = stateMachine.connect()

    let results = try await [connection1, connection2, connection3]

    XCTAssertEqual(connectCallCount, 1, "Should only connect once despite concurrent calls")
    XCTAssertTrue(results.allSatisfy { $0 === mockWebSocket })
  }

  func testDisconnectClosesConnection() async throws {
    stateMachine = makeStateMachine()

    _ = try await stateMachine.connect()
    XCTAssertFalse(mockWebSocket.isClosed)

    await stateMachine.disconnect(reason: "test disconnect")

    XCTAssertTrue(mockWebSocket.isClosed)
    XCTAssertEqual(mockWebSocket.closeReason, "test disconnect")

    let isConnected = await stateMachine.isConnected
    XCTAssertFalse(isConnected)
  }

  func testDisconnectWhenDisconnectedIsNoop() async {
    stateMachine = makeStateMachine()

    // Should not crash
    await stateMachine.disconnect()

    let isConnected = await stateMachine.isConnected
    XCTAssertFalse(isConnected)
  }

  func testHandleErrorTriggersReconnect() async throws {
    stateMachine = makeStateMachine(reconnectDelay: 0.05)

    _ = try await stateMachine.connect()
    XCTAssertEqual(connectCallCount, 1)

    // Simulate error
    await stateMachine.handleError(NSError(domain: "test", code: 1))

    // Wait for reconnect delay
    try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

    // Should have reconnected
    XCTAssertEqual(connectCallCount, 2, "Should have reconnected after error")
  }

  func testHandleCloseDisconnects() async throws {
    stateMachine = makeStateMachine()

    _ = try await stateMachine.connect()

    await stateMachine.handleClose(code: 1000, reason: "normal closure")

    let isConnected = await stateMachine.isConnected
    XCTAssertFalse(isConnected)
  }

  func testHandleDisconnectedTriggersReconnect() async throws {
    stateMachine = makeStateMachine(reconnectDelay: 0.05)

    _ = try await stateMachine.connect()
    XCTAssertEqual(connectCallCount, 1)

    await stateMachine.handleDisconnected()

    // Wait for reconnect
    try await Task.sleep(nanoseconds: 100_000_000)

    XCTAssertEqual(connectCallCount, 2, "Should have reconnected")
  }

  func testDisconnectCancelsReconnection() async throws {
    stateMachine = makeStateMachine(reconnectDelay: 0.2)

    _ = try await stateMachine.connect()

    // Trigger reconnection
    await stateMachine.handleError(NSError(domain: "test", code: 1))

    // Immediately disconnect before reconnection completes
    await stateMachine.disconnect()

    // Wait longer than reconnect delay
    try await Task.sleep(nanoseconds: 300_000_000)

    // Should only have connected once (reconnection was cancelled)
    XCTAssertEqual(connectCallCount, 1)
  }
}
