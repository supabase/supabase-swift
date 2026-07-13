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
    func testSocketsDeallocateAfterClose() async throws {
      let server = try LoopbackWebSocketServer()
      let port = try server.start()
      defer { server.stop() }

      let url = URL(string: "ws://127.0.0.1:\(port)")!

      var deallocations: [XCTestExpectation] = []

      for index in 0..<5 {
        let deallocated = expectation(description: "socket \(index) deallocated")
        deallocations.append(deallocated)

        let socket = try await URLSessionWebSocket.connect(to: url)
        objc_setAssociatedObject(
          socket,
          &deinitNotifierKey,
          DeinitNotifier { deallocated.fulfill() },
          .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        socket.close(code: 1000, reason: nil)
      }

      await fulfillment(of: deallocations, timeout: 10)
    }
  #endif

  // MARK: - _Delegate Auth Challenge Forwarding Tests

  /// No-op sender required by `URLAuthenticationChallenge`'s designated initializer.
  /// Never invoked: these tests exercise `_Delegate` directly rather than through a
  /// live challenge-response cycle.
  private final class NoopChallengeSender: NSObject, URLAuthenticationChallengeSender {
    func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {}
    func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {}
    func cancel(_ challenge: URLAuthenticationChallenge) {}
  }

  private func makeChallenge() -> URLAuthenticationChallenge {
    let protectionSpace = URLProtectionSpace(
      host: "example.com", port: 443, protocol: "https", realm: nil,
      authenticationMethod: NSURLAuthenticationMethodServerTrust)
    return URLAuthenticationChallenge(
      protectionSpace: protectionSpace, proposedCredential: nil, previousFailureCount: 0,
      failureResponse: nil, error: nil, sender: NoopChallengeSender())
  }

  func testChallengeForwardedToTaskLevelWrappedDelegate() {
    final class TaskDelegate: NSObject, URLSessionTaskDelegate {
      var receivedChallenge: URLAuthenticationChallenge?
      func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
      ) {
        receivedChallenge = challenge
        completionHandler(.useCredential, nil)
      }
    }

    let wrappedDelegate = TaskDelegate()
    let delegate = _Delegate(
      onComplete: nil,
      onWebSocketTaskOpened: nil,
      onWebSocketTaskClosed: nil,
      wrappedDelegate: wrappedDelegate
    )

    let session = URLSession(configuration: .default)
    let task = session.dataTask(with: URL(string: "https://example.com")!)
    let challenge = makeChallenge()

    let expectation = expectation(description: "completion handler called")
    delegate.urlSession(session, task: task, didReceive: challenge) { disposition, _ in
      XCTAssertEqual(disposition, .useCredential)
      expectation.fulfill()
    }

    wait(for: [expectation], timeout: 1)
    XCTAssertNotNil(wrappedDelegate.receivedChallenge)
  }

  func testChallengeForwardedToSessionLevelWrappedDelegateWhenTaskLevelNotImplemented() {
    final class LegacyDelegate: NSObject, URLSessionDelegate {
      var receivedChallenge: URLAuthenticationChallenge?
      func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
      ) {
        receivedChallenge = challenge
        completionHandler(.cancelAuthenticationChallenge, nil)
      }
    }

    let wrappedDelegate = LegacyDelegate()
    let delegate = _Delegate(
      onComplete: nil,
      onWebSocketTaskOpened: nil,
      onWebSocketTaskClosed: nil,
      wrappedDelegate: wrappedDelegate
    )

    let session = URLSession(configuration: .default)
    let task = session.dataTask(with: URL(string: "https://example.com")!)
    let challenge = makeChallenge()

    let expectation = expectation(description: "completion handler called")
    delegate.urlSession(session, task: task, didReceive: challenge) { disposition, _ in
      XCTAssertEqual(disposition, .cancelAuthenticationChallenge)
      expectation.fulfill()
    }

    wait(for: [expectation], timeout: 1)
    XCTAssertNotNil(wrappedDelegate.receivedChallenge)
  }

  func testChallengeDefaultsToPerformDefaultHandlingWhenNoWrappedDelegate() {
    let delegate = _Delegate(
      onComplete: nil,
      onWebSocketTaskOpened: nil,
      onWebSocketTaskClosed: nil,
      wrappedDelegate: nil
    )

    let session = URLSession(configuration: .default)
    let task = session.dataTask(with: URL(string: "https://example.com")!)
    let challenge = makeChallenge()

    let expectation = expectation(description: "completion handler called")
    delegate.urlSession(session, task: task, didReceive: challenge) { disposition, credential in
      XCTAssertEqual(disposition, .performDefaultHandling)
      XCTAssertNil(credential)
      expectation.fulfill()
    }

    wait(for: [expectation], timeout: 1)
  }
}

#if canImport(Network)
  import Network
  import ObjectiveC

  private final class DeinitNotifier {
    private let onDeinit: @Sendable () -> Void
    init(_ onDeinit: @escaping @Sendable () -> Void) { self.onDeinit = onDeinit }
    deinit { onDeinit() }
  }

  private nonisolated(unsafe) var deinitNotifierKey: UInt8 = 0

  private final class LoopbackWebSocketServer {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "co.supabase.LoopbackWebSocketServer")
    private var connections: [NWConnection] = []
    private var isStopped = false

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
        if self.isStopped {
          connection.cancel()
          return
        }
        self.connections.append(connection)
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
      connection.receiveMessage { [weak self] _, context, _, error in
        if let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition)
          as? NWProtocolWebSocket.Metadata, metadata.opcode == .close
        {
          let closeMetadata = NWProtocolWebSocket.Metadata(opcode: .close)
          let closeContext = NWConnection.ContentContext(
            identifier: "close", metadata: [closeMetadata])
          connection.send(
            content: nil,
            contentContext: closeContext,
            isComplete: true,
            completion: .contentProcessed { _ in connection.cancel() }
          )
          return
        }

        guard error == nil else { return }
        self?.receive(on: connection)
      }
    }

    func stop() {
      queue.sync {
        isStopped = true
        listener.cancel()
        for connection in connections { connection.cancel() }
        connections.removeAll()
      }
    }
  }
#endif
