import ConcurrencyExtras
import Foundation
import Testing

@testable import Realtime
@testable import RealtimeV2

@Suite
struct ConnectionManagerTests {
  private enum TestError: LocalizedError {
    case sample

    var errorDescription: String? { "sample error" }
  }

  let ws: FakeWebSocket
  let transportCallCount = LockIsolated(0)
  let lastConnectURL = LockIsolated<URL?>(nil)
  let lastConnectHeaders = LockIsolated<[String: String]?>(nil)

  init() {
    (ws, _) = FakeWebSocket.fakes()
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
        return ws
      },
      url: url,
      headers: headers,
      reconnectDelay: reconnectDelay,
      logger: nil,
      clock: ContinuousClock()
    )
  }

  @Test
  func connectTransitionsThroughConnectingAndConnectedStates() async throws {
    let sut = makeSUT(headers: ["apikey": "key"])

    let connectingObserved = LockIsolated(false)
    let connectedObserved = LockIsolated(false)

    let stateObserver = Task {
      for await state in sut.stateChanges {
        switch state {
        case .connecting:
          connectingObserved.setValue(true)
        case .connected:
          connectedObserved.setValue(true)
          return
        default:
          break
        }
      }
    }

    let initiallyConnected = await sut.connection != nil
    #expect(!initiallyConnected)
    try await sut.connect()

    let isConnected = await sut.connection != nil
    #expect(isConnected)
    #expect(transportCallCount.value == 1)
    #expect(lastConnectURL.value?.absoluteString == "ws://localhost")
    #expect(lastConnectHeaders.value == ["apikey": "key"])

    let observedBoth = await waitUntil(timeout: 1) {
      connectingObserved.value && connectedObserved.value
    }
    #expect(observedBoth)
    stateObserver.cancel()
  }

  @Test
  func connectWhenAlreadyConnectedDoesNotReconnect() async throws {
    let sut = makeSUT()

    try await sut.connect()
    #expect(transportCallCount.value == 1)

    try await sut.connect()

    let stillConnected = await sut.connection != nil
    #expect(stillConnected)
    #expect(transportCallCount.value == 1, "Second connect should reuse existing connection")
  }

  @Test
  func connectWhileConnectingWaitsForExistingTask() async throws {
    let transportCallCount = self.transportCallCount
    let ws = self.ws
    let sut = makeSUT(
      transport: { _, _ in
        transportCallCount.withValue { $0 += 1 }
        try await Task.sleep(nanoseconds: 200_000_000)
        return ws
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

    let transportCalled = await waitUntil { transportCallCount.value == 1 }
    #expect(transportCalled, "Transport should be invoked while first connect is in progress")
    #expect(!secondConnectFinished.value)
    #expect(
      transportCallCount.value == 1,
      "Transport should be invoked only once while first connect is in progress")

    _ = try await firstConnect.value
    try await secondConnect.value

    #expect(secondConnectFinished.value)
    let isConnected = await sut.connection != nil
    #expect(isConnected)
    #expect(transportCallCount.value == 1)
  }

  @Test
  func disconnectFromConnectedClosesWebSocketAndUpdatesState() async throws {
    let sut = makeSUT()
    try await sut.connect()

    await sut.disconnect(reason: "test reason")

    let isConnected = await sut.connection != nil
    #expect(!isConnected)
    guard case .close(let closeCode, let closeReason)? = ws.sentEvents.last else {
      Issue.record("Expected close event to be sent")
      return
    }
    #expect(closeCode == nil)
    #expect(closeReason == "test reason")
  }

  @Test
  func disconnectCancelsOngoingConnectionAttempt() async throws {
    let wasCancelled = LockIsolated(false)
    let transportCallCount = self.transportCallCount
    let ws = self.ws

    let sut = makeSUT(
      transport: { _, _ in
        transportCallCount.withValue { $0 += 1 }
        return try await withTaskCancellationHandler {
          try await Task.sleep(nanoseconds: 5_000_000_000)
          return ws
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
    #expect(wasCancelled.value, "Cancellation handler should run when disconnecting")
    let isConnected = await sut.connection != nil
    #expect(!isConnected)

    connectTask.cancel()
  }

  @Test
  func handleErrorInitiatesReconnectAndEventuallyReconnects() async throws {
    let reconnectingObserved = LockIsolated(false)
    let secondConnectionObserved = LockIsolated(false)

    let connectionCount = LockIsolated(0)
    let ws = self.ws

    let sut = makeSUT(
      reconnectDelay: 0.01,
      transport: { _, _ in
        connectionCount.withValue { $0 += 1 }
        if connectionCount.value == 2 {
          secondConnectionObserved.setValue(true)
        }
        return ws
      }
    )

    let stateObserver = Task {
      for await state in sut.stateChanges {
        if case .reconnecting(_, let reason) = state, reason.contains("sample error") {
          reconnectingObserved.setValue(true)
          return
        }
      }
    }

    try await sut.connect()
    await sut.handleError(TestError.sample)

    let observedBoth = await waitUntil(timeout: 2) {
      reconnectingObserved.value && secondConnectionObserved.value
    }
    #expect(observedBoth)
    #expect(connectionCount.value == 2, "Reconnection should trigger a second transport call")
    let isConnected = await sut.connection != nil
    #expect(isConnected)

    stateObserver.cancel()
  }

  @Test
  func handleCloseUpdatesStateWithoutSendingAnotherCloseFrame() async throws {
    let sut = makeSUT()
    try await sut.connect()

    let sentEventsBefore = ws.sentEvents.count
    await sut.handleClose(code: 4001, reason: "server closing")

    let isConnected = await sut.connection != nil
    #expect(!isConnected)
    #expect(
      ws.sentEvents.count == sentEventsBefore,
      "handleClose should not send an additional close frame since the remote already closed."
    )
  }

  @Test
  func handleCloseFromStaleConnectionIsIgnored() async throws {
    let (staleWS, _) = FakeWebSocket.fakes()
    let sut = makeSUT()
    try await sut.connect()

    // A late .close from a previous socket must not mark the current
    // connection as disconnected.
    await sut.handleClose(code: 1006, reason: "stale socket closed", from: staleWS)

    let isConnected = await sut.connection != nil
    #expect(isConnected, "Close from a stale connection should be ignored")
  }

  @Test
  func handleErrorFromStaleConnectionIsIgnored() async throws {
    let (staleWS, _) = FakeWebSocket.fakes()
    let sut = makeSUT()
    try await sut.connect()

    await sut.handleError(TestError.sample, from: staleWS)

    let isConnected = await sut.connection != nil
    #expect(isConnected, "Error from a stale connection should be ignored")
    #expect(
      transportCallCount.value == 1,
      "Error from a stale connection should not trigger a reconnect"
    )
  }

  @Test
  func handleErrorFromCurrentConnectionInitiatesReconnect() async throws {
    let sut = makeSUT(reconnectDelay: 0.01)
    try await sut.connect()

    await sut.handleError(TestError.sample, from: ws)

    // Wait for the reconnect to complete.
    let transportCallCount = self.transportCallCount
    let reconnected = await waitUntil(timeout: 5) { transportCallCount.value >= 2 }
    #expect(reconnected)

    #expect(
      transportCallCount.value == 2,
      "Error from the current connection should trigger a reconnect"
    )
  }

  @Test
  func handleCloseInitiatesReconnectAndEventuallyReconnects() async throws {
    let reconnectingObserved = LockIsolated(false)
    let secondConnectionObserved = LockIsolated(false)

    let connectionCount = LockIsolated(0)
    let ws = self.ws

    let sut = makeSUT(
      reconnectDelay: 0.01,
      transport: { _, _ in
        connectionCount.withValue { $0 += 1 }
        if connectionCount.value == 2 {
          secondConnectionObserved.setValue(true)
        }
        return ws
      }
    )

    let stateObserver = Task {
      for await state in sut.stateChanges {
        if case .reconnecting(_, let reason) = state, reason.contains("1001") {
          reconnectingObserved.setValue(true)
          return
        }
      }
    }

    try await sut.connect()
    // Use a transport-level close code (1001 = going away) to exercise the
    // reconnect path. Application-level codes (4000–4999) skip reconnect.
    await sut.handleClose(code: 1001, reason: "server restart")

    let observedBoth = await waitUntil(timeout: 2) {
      reconnectingObserved.value && secondConnectionObserved.value
    }
    #expect(observedBoth)
    #expect(connectionCount.value == 2, "Remote close should trigger a reconnection attempt")
    let isConnected = await sut.connection != nil
    #expect(isConnected)

    stateObserver.cancel()
  }

  @Test
  func handleCloseDoesNotReconnectForApplicationCloseCode() async throws {
    let sut = makeSUT(reconnectDelay: 0.01)
    try await sut.connect()

    // Application-level close codes (4000–4999) must not trigger automatic
    // reconnect — the caller needs to re-authenticate before reconnecting,
    // otherwise reconnecting with the same bad token just loops.
    await sut.handleClose(code: 4001, reason: "jwt expired")

    // Brief wait to confirm the reconnect task does not fire.
    try await Task.sleep(nanoseconds: 50_000_000)

    #expect(
      transportCallCount.value == 1,
      "Application close code (4001) must not trigger reconnect"
    )
    let isConnected = await sut.connection != nil
    #expect(!isConnected, "Connection should be disconnected after application close")
  }
}
