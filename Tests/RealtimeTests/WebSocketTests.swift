//
//  WebSocketTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 29/07/25.
//

import ConcurrencyExtras
import XCTest

@testable import Realtime
@testable import RealtimeV2

final class WebSocketTests: XCTestCase {

  // MARK: - WebSocketEvent Tests

  func testWebSocketEventEquality() {
    let textEvent1 = WebSocketEvent.text("hello")
    let textEvent2 = WebSocketEvent.text("hello")
    let textEvent3 = WebSocketEvent.text("world")

    XCTAssertEqual(textEvent1, textEvent2)
    XCTAssertNotEqual(textEvent1, textEvent3)

    let binaryData = Data([1, 2, 3])
    let binaryEvent1 = WebSocketEvent.binary(binaryData)
    let binaryEvent2 = WebSocketEvent.binary(binaryData)
    let binaryEvent3 = WebSocketEvent.binary(Data([4, 5, 6]))

    XCTAssertEqual(binaryEvent1, binaryEvent2)
    XCTAssertNotEqual(binaryEvent1, binaryEvent3)

    let closeEvent1 = WebSocketEvent.close(code: 1000, reason: "normal")
    let closeEvent2 = WebSocketEvent.close(code: 1000, reason: "normal")
    let closeEvent3 = WebSocketEvent.close(code: 1001, reason: "going away")

    XCTAssertEqual(closeEvent1, closeEvent2)
    XCTAssertNotEqual(closeEvent1, closeEvent3)
  }

  func testWebSocketEventHashable() {
    let textEvent = WebSocketEvent.text("hello")
    let binaryEvent = WebSocketEvent.binary(Data([1, 2, 3]))
    let closeEvent = WebSocketEvent.close(code: 1000, reason: "normal")

    let events: Set<WebSocketEvent> = [textEvent, binaryEvent, closeEvent]
    XCTAssertEqual(events.count, 3)
  }

  func testWebSocketEventPatternMatching() {
    let textEvent = WebSocketEvent.text("hello world")
    let binaryEvent = WebSocketEvent.binary(Data([1, 2, 3]))
    let closeEvent = WebSocketEvent.close(code: 1000, reason: "normal")

    switch textEvent {
    case .text(let message):
      XCTAssertEqual(message, "hello world")
    default:
      XCTFail("Expected text event")
    }

    switch binaryEvent {
    case .binary(let data):
      XCTAssertEqual(data, Data([1, 2, 3]))
    default:
      XCTFail("Expected binary event")
    }

    switch closeEvent {
    case .close(let code, let reason):
      XCTAssertEqual(code, 1000)
      XCTAssertEqual(reason, "normal")
    default:
      XCTFail("Expected close event")
    }
  }

  // MARK: - WebSocketError Tests

  func testWebSocketErrorConnection() {
    let underlyingError = NSError(
      domain: "TestDomain", code: 123, userInfo: [NSLocalizedDescriptionKey: "Test error"])
    let webSocketError = WebSocketError.connection(
      message: "Connection failed", error: underlyingError)

    XCTAssertEqual(webSocketError.errorDescription, "Connection failed Test error")
  }

  func testWebSocketErrorAsError() {
    let underlyingError = NSError(
      domain: "TestDomain", code: 123, userInfo: [NSLocalizedDescriptionKey: "Test error"])
    let webSocketError = WebSocketError.connection(
      message: "Connection failed", error: underlyingError)
    let error: Error = webSocketError

    XCTAssertEqual(error.localizedDescription, "Connection failed Test error")
  }

  // MARK: - URLSessionWebSocket Lifecycle Tests

  #if canImport(Network)
    func testSocketDeallocatesAfterClose() async throws {
      let server = try LoopbackWebSocketServer()
      let port = try server.start()
      defer { server.stop() }

      let url = URL(string: "ws://127.0.0.1:\(port)")!

      weak var weakSocket: URLSessionWebSocket?

      func connectCloseAndDrop() async throws {
        let socket = try await URLSessionWebSocket.connect(to: url)
        weakSocket = socket
        socket.close(code: 1000, reason: nil)
      }

      try await connectCloseAndDrop()

      let deadline = Date().addingTimeInterval(5)
      while weakSocket != nil, Date() < deadline {
        try await Task.sleep(nanoseconds: 10_000_000)
      }

      XCTAssertNil(
        weakSocket,
        "URLSessionWebSocket leaked after close: its delegate-backed URLSession was never invalidated"
      )
    }
  #endif
}

#if canImport(Network)
  import Network

  private final class LoopbackWebSocketServer {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "co.supabase.LoopbackWebSocketServer")
    private var connections: [NWConnection] = []

    init() throws {
      let parameters = NWParameters.tcp
      let webSocketOptions = NWProtocolWebSocket.Options()
      webSocketOptions.autoReplyPing = true
      parameters.defaultProtocolStack.applicationProtocols.insert(webSocketOptions, at: 0)
      listener = try NWListener(using: parameters, on: .any)
    }

    func start() throws -> UInt16 {
      let ready = DispatchSemaphore(value: 0)

      listener.stateUpdateHandler = { state in
        if case .ready = state { ready.signal() }
      }

      listener.newConnectionHandler = { [weak self] connection in
        guard let self else { return }
        self.queue.async { self.connections.append(connection) }
        connection.start(queue: self.queue)
        self.receive(on: connection)
      }

      listener.start(queue: queue)

      guard ready.wait(timeout: .now() + 5) == .success, let port = listener.port else {
        throw WebSocketError.connection(
          message: "loopback server failed to start",
          error: NSError(domain: "LoopbackWebSocketServer", code: -1)
        )
      }

      return port.rawValue
    }

    private func receive(on connection: NWConnection) {
      connection.receiveMessage { [weak self] _, _, _, error in
        guard error == nil else { return }
        self?.receive(on: connection)
      }
    }

    func stop() {
      queue.sync {
        for connection in connections { connection.cancel() }
        connections.removeAll()
      }
      listener.cancel()
    }
  }
#endif
