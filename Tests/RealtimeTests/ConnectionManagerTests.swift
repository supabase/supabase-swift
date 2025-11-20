//
//  ConnectionManagerTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 19/11/25.
//

import ConcurrencyExtras
import XCTest

@testable import Realtime

final class ConnectionManagerTests: XCTestCase {
  private enum TestError: LocalizedError {
    case sample

    var errorDescription: String? { "sample error" }
  }

  let url = URL(string: "ws://localhost")!
  let headers = ["apikey": "key"]

  var sut: ConnectionManager!
  var ws: FakeWebSocket!
  var transportCallCount = 0
  var lastConnectURL: URL?
  var lastConnectHeaders: [String: String]?

  override func setUp() {
    super.setUp()

    transportCallCount = 0
    lastConnectURL = nil
    lastConnectHeaders = nil
    (ws, _) = FakeWebSocket.fakes()
  }

  override func tearDown() {
    sut = nil
    ws = nil
    super.tearDown()
  }

  private func makeSUT(
    url: URL = URL(string: "ws://localhost")!,
    headers: [String: String] = [:],
    reconnectDelay: TimeInterval = 0.1,
    transport: WebSocketTransport? = nil
  ) -> ConnectionManager {
    ConnectionManager(
      transport: transport ?? { url, headers in
        self.transportCallCount += 1
        self.lastConnectURL = url
        self.lastConnectHeaders = headers
        return self.ws!
      },
      url: url,
      headers: headers,
      reconnectDelay: reconnectDelay,
      logger: nil
    )
  }

  func testConnectTransitionsThroughConnectingAndConnectedStates() async throws {
    sut = makeSUT(url: url, headers: headers)

    let connectingExpectation = expectation(description: "connecting state observed")
    let connectedExpectation = expectation(description: "connected state observed")

    let stateObserver = Task {
      for await state in await sut.stateChanges {
        switch state {
        case .connecting:
          connectingExpectation.fulfill()
        case .connected:
          connectedExpectation.fulfill()
          return
        default:
          break
        }
      }
    }

    let initiallyConnected = await sut.isConnected
    XCTAssertFalse(initiallyConnected)
    try await sut.connect()

    let isConnected = await sut.isConnected
    XCTAssertTrue(isConnected)
    XCTAssertEqual(transportCallCount, 1)
    XCTAssertEqual(lastConnectURL, url)
    XCTAssertEqual(lastConnectHeaders, headers)

    await fulfillment(of: [connectingExpectation, connectedExpectation], timeout: 1)
    stateObserver.cancel()
  }

  func testConnectWhenAlreadyConnectedDoesNotReconnect() async throws {
    sut = makeSUT()

    try await sut.connect()
    XCTAssertEqual(transportCallCount, 1)

    try await sut.connect()

    let stillConnected = await sut.isConnected
    XCTAssertTrue(stillConnected)
    XCTAssertEqual(transportCallCount, 1, "Second connect should reuse existing connection")
  }

  func testConnectWhileConnectingWaitsForExistingTask() async throws {
    sut = makeSUT(
      transport: { _, _ in
        self.transportCallCount += 1
        try await Task.sleep(nanoseconds: 200_000_000)
        return self.ws!
      }
    )

    let firstConnect = Task {
      try await sut.connect()
    }

    let secondConnectFinished = LockIsolated(false)
    let secondConnect = Task {
      try await sut.connect()
      secondConnectFinished.setValue(true)
    }

    try await Task.sleep(nanoseconds: 50_000_000)
    XCTAssertFalse(secondConnectFinished.value)
    XCTAssertEqual(
      transportCallCount, 1,
      "Transport should be invoked only once while first connect is in progress")

    try await firstConnect.value
    try await secondConnect.value

    XCTAssertTrue(secondConnectFinished.value)
    let isConnected = await sut.isConnected
    XCTAssertTrue(isConnected)
    XCTAssertEqual(transportCallCount, 1)
  }

  func testDisconnectFromConnectedClosesWebSocketAndUpdatesState() async throws {
    sut = makeSUT()
    try await sut.connect()

    await sut.disconnect(reason: "test reason")

    let isConnected = await sut.isConnected
    XCTAssertFalse(isConnected)
    guard case .close(let closeCode, let closeReason)? = ws.sentEvents.last else {
      return XCTFail("Expected close event to be sent")
    }
    XCTAssertNil(closeCode)
    XCTAssertEqual(closeReason, "test reason")
  }

  func testDisconnectCancelsOngoingConnectionAttempt() async throws {
    let wasCancelled = LockIsolated(false)

    sut = makeSUT(
      transport: { _, _ in
        self.transportCallCount += 1
        return try await withTaskCancellationHandler {
          try await Task.sleep(nanoseconds: 5_000_000_000)
          return self.ws!
        } onCancel: {
          wasCancelled.setValue(true)
        }
      }
    )

    let connectTask = Task {
      try? await sut.connect()
    }

    try await Task.sleep(nanoseconds: 50_000_000)
    await sut.disconnect(reason: "stop")

    await Task.yield()
    XCTAssertTrue(wasCancelled.value, "Cancellation handler should run when disconnecting")
    let isConnected = await sut.isConnected
    XCTAssertFalse(isConnected)

    connectTask.cancel()
  }

  func testHandleErrorInitiatesReconnectAndEventuallyReconnects() async throws {
    let reconnectingExpectation = expectation(description: "reconnecting state observed")
    let secondConnectionExpectation = expectation(description: "second connection attempt")

    let connectionCount = LockIsolated(0)

    sut = makeSUT(
      reconnectDelay: 0.01,
      transport: { _, _ in
        connectionCount.withValue { $0 += 1 }
        if connectionCount.value == 2 {
          secondConnectionExpectation.fulfill()
        }
        return self.ws!
      }
    )

    let stateObserver = Task {
      for await state in await sut.stateChanges {
        if case .reconnecting(_, let reason) = state, reason.contains("sample error") {
          reconnectingExpectation.fulfill()
          return
        }
      }
    }

    try await sut.connect()
    await sut.handleError(TestError.sample)

    await fulfillment(of: [reconnectingExpectation, secondConnectionExpectation], timeout: 2)
    XCTAssertEqual(connectionCount.value, 2, "Reconnection should trigger a second transport call")
    let isConnected = await sut.isConnected
    XCTAssertTrue(isConnected)

    stateObserver.cancel()
  }

  func testHandleCloseDelegatesToDisconnect() async throws {
    sut = makeSUT()
    try await sut.connect()

    await sut.handleClose(code: 4001, reason: "server closing")

    let isConnected = await sut.isConnected
    XCTAssertFalse(isConnected)
    guard case .close(let closeCode, let closeReason)? = ws.sentEvents.last else {
      return XCTFail("Expected close event to be sent")
    }
    XCTAssertNil(closeCode)
    XCTAssertEqual(closeReason, "server closing")
  }
}
