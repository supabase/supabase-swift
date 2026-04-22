import ConcurrencyExtras
import XCTest

@testable import Realtime

final class ConnectionManagerTests: XCTestCase {
  private enum TestError: LocalizedError {
    case sample

    var errorDescription: String? { "sample error" }
  }

  var sut: ConnectionManager!
  var ws: FakeWebSocket!
  let transportCallCount = LockIsolated(0)
  let lastConnectURL = LockIsolated<URL?>(nil)
  let lastConnectHeaders = LockIsolated<[String: String]?>(nil)

  override func setUp() {
    super.setUp()

    transportCallCount.setValue(0)
    lastConnectURL.setValue(nil)
    lastConnectHeaders.setValue(nil)
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
    let transportCallCount = self.transportCallCount
    let lastConnectURL = self.lastConnectURL
    let lastConnectHeaders = self.lastConnectHeaders
    let ws = self.ws
    return ConnectionManager(
      transport: transport ?? { url, headers in
        transportCallCount.withValue { $0 += 1 }
        lastConnectURL.setValue(url)
        lastConnectHeaders.setValue(headers)
        return ws!
      },
      url: url,
      headers: headers,
      reconnectDelay: reconnectDelay,
      logger: nil
    )
  }

  func testConnectTransitionsThroughConnectingAndConnectedStates() async throws {
    sut = makeSUT(headers: ["apikey": "key"])

    let connectingExpectation = expectation(description: "connecting state observed")
    let connectedExpectation = expectation(description: "connected state observed")

    let stateObserver = Task {
      for await state in sut.stateChanges {
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

    let initiallyConnected = await sut.connection != nil
    XCTAssertFalse(initiallyConnected)
    try await sut.connect()

    let isConnected = await sut.connection != nil
    XCTAssertTrue(isConnected)
    XCTAssertEqual(transportCallCount.value, 1)
    XCTAssertEqual(lastConnectURL.value?.absoluteString, "ws://localhost")
    XCTAssertEqual(lastConnectHeaders.value, ["apikey": "key"])

    await fulfillment(of: [connectingExpectation, connectedExpectation], timeout: 1)
    stateObserver.cancel()
  }

  func testConnectWhenAlreadyConnectedDoesNotReconnect() async throws {
    sut = makeSUT()

    try await sut.connect()
    XCTAssertEqual(transportCallCount.value, 1)

    try await sut.connect()

    let stillConnected = await sut.connection != nil
    XCTAssertTrue(stillConnected)
    XCTAssertEqual(transportCallCount.value, 1, "Second connect should reuse existing connection")
  }

  func testConnectWhileConnectingWaitsForExistingTask() async throws {
    let transportCallCount = self.transportCallCount
    let ws = self.ws
    sut = makeSUT(
      transport: { _, _ in
        transportCallCount.withValue { $0 += 1 }
        try await Task.sleep(nanoseconds: 200_000_000)
        return ws!
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
      transportCallCount.value, 1,
      "Transport should be invoked only once while first connect is in progress")

    _ = try await firstConnect.value
    try await secondConnect.value

    XCTAssertTrue(secondConnectFinished.value)
    let isConnected = await sut.connection != nil
    XCTAssertTrue(isConnected)
    XCTAssertEqual(transportCallCount.value, 1)
  }

  func testDisconnectFromConnectedClosesWebSocketAndUpdatesState() async throws {
    sut = makeSUT()
    try await sut.connect()

    await sut.disconnect(reason: "test reason")

    let isConnected = await sut.connection != nil
    XCTAssertFalse(isConnected)
    guard case .close(let closeCode, let closeReason)? = ws.sentEvents.last else {
      return XCTFail("Expected close event to be sent")
    }
    XCTAssertNil(closeCode)
    XCTAssertEqual(closeReason, "test reason")
  }

  func testDisconnectCancelsOngoingConnectionAttempt() async throws {
    let wasCancelled = LockIsolated(false)
    let transportCallCount = self.transportCallCount
    let ws = self.ws

    sut = makeSUT(
      transport: { _, _ in
        transportCallCount.withValue { $0 += 1 }
        return try await withTaskCancellationHandler {
          try await Task.sleep(nanoseconds: 5_000_000_000)
          return ws!
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
    let isConnected = await sut.connection != nil
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
      for await state in sut.stateChanges {
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
    let isConnected = await sut.connection != nil
    XCTAssertTrue(isConnected)

    stateObserver.cancel()
  }

  func testHandleCloseUpdatesStateWithoutSendingAnotherCloseFrame() async throws {
    sut = makeSUT()
    try await sut.connect()

    let sentEventsBefore = ws.sentEvents.count
    await sut.handleClose(code: 4001, reason: "server closing")

    let isConnected = await sut.connection != nil
    XCTAssertFalse(isConnected)
    XCTAssertEqual(
      ws.sentEvents.count, sentEventsBefore,
      "handleClose should not send an additional close frame since the remote already closed."
    )
  }
}
