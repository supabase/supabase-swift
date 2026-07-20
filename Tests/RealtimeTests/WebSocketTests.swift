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

    func testConnectAcceptsSessionWithADelegateAsATemplate() async throws {
      final class RecordingDelegate: NSObject, URLSessionDelegate {}

      let server = try LoopbackWebSocketServer()
      let port = try server.start()
      defer { server.stop() }

      let url = URL(string: "ws://127.0.0.1:\(port)")!
      let delegate = RecordingDelegate()
      let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

      let socket = try await URLSessionWebSocket.connect(to: url, session: session)
      socket.close(code: 1000, reason: nil)
    }

    func testCallerSuppliedSessionIsNeverUsedDirectlyOrInvalidated() async throws {
      let server = try LoopbackWebSocketServer()
      let port = try server.start()
      defer { server.stop() }

      let url = URL(string: "ws://127.0.0.1:\(port)")!
      // A session the caller owns and may keep using elsewhere (e.g. shared with
      // Auth/PostgREST/Storage) — `connect` must only read its `configuration`/`delegate`
      // as a template, never use or invalidate the object itself.
      let session = URLSession(configuration: .default)

      let firstSocket = try await URLSessionWebSocket.connect(to: url, session: session)
      firstSocket.close(code: 1000, reason: nil)

      // `finishTasksAndInvalidate()` invalidates asynchronously via a delegate callback;
      // give it time to take effect before checking whether the session still works.
      try await Task.sleep(for: .milliseconds(200))

      // If `connect` had used `session` directly and invalidated it on close (the bug this
      // test guards against), reusing it for a second connection would fail — URLSession
      // refuses to schedule new work on an invalidated session.
      let secondSocket = try await URLSessionWebSocket.connect(to: url, session: session)
      secondSocket.close(code: 1000, reason: nil)
    }

    #if os(macOS)
      func testCertPinningAcceptsMatchingCertificate() async throws {
        let (identity, certificateData) = try makeSelfSignedIdentity()
        let server = try LoopbackTLSWebSocketServer(identity: identity)
        let port = try server.start()
        defer { server.stop() }

        let url = URL(string: "wss://127.0.0.1:\(port)")!
        let delegate = PinningSessionDelegate(expectedCertificateData: certificateData)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

        let socket = try await URLSessionWebSocket.connect(to: url, session: session)
        socket.close(code: 1000, reason: nil)

        XCTAssertTrue(delegate.wasInvoked)
      }

      func testCertPinningRejectsMismatchedCertificate() async throws {
        let (identity, _) = try makeSelfSignedIdentity()
        let (_, wrongCertificateData) = try makeSelfSignedIdentity()
        let server = try LoopbackTLSWebSocketServer(identity: identity)
        let port = try server.start()
        defer { server.stop() }

        let url = URL(string: "wss://127.0.0.1:\(port)")!
        let delegate = PinningSessionDelegate(expectedCertificateData: wrongCertificateData)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

        do {
          _ = try await URLSessionWebSocket.connect(to: url, session: session)
          XCTFail("expected connection to fail due to certificate mismatch")
        } catch {
          // Expected: the pinning delegate rejected the server's certificate, so the
          // TLS handshake failed and `connect` threw.
        }

        XCTAssertTrue(delegate.wasInvoked)
      }

      func testCertPinningAcceptsMatchingCertificateWithTaskLevelDelegate() async throws {
        let (identity, certificateData) = try makeSelfSignedIdentity()
        let server = try LoopbackTLSWebSocketServer(identity: identity)
        let port = try server.start()
        defer { server.stop() }

        let url = URL(string: "wss://127.0.0.1:\(port)")!
        // A delegate implementing only the modern, task-level challenge method — the exact
        // shape that a per-task `_Delegate.urlSession(_:didReceive:completionHandler:)`
        // (session-level only) previously failed to forward to. `associatedTask` is what
        // makes this work now; this test proves it over a real TLS handshake, not just a
        // direct unit-test call into `_Delegate`.
        let delegate = PinningTaskDelegate(expectedCertificateData: certificateData)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

        let socket = try await URLSessionWebSocket.connect(to: url, session: session)
        socket.close(code: 1000, reason: nil)

        XCTAssertTrue(delegate.wasInvoked)
      }

      func testCertPinningRejectsMismatchedCertificateWithTaskLevelDelegate() async throws {
        let (identity, _) = try makeSelfSignedIdentity()
        let (_, wrongCertificateData) = try makeSelfSignedIdentity()
        let server = try LoopbackTLSWebSocketServer(identity: identity)
        let port = try server.start()
        defer { server.stop() }

        let url = URL(string: "wss://127.0.0.1:\(port)")!
        let delegate = PinningTaskDelegate(expectedCertificateData: wrongCertificateData)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

        do {
          _ = try await URLSessionWebSocket.connect(to: url, session: session)
          XCTFail("expected connection to fail due to certificate mismatch")
        } catch {
          // Expected: the pinning delegate rejected the server's certificate, so the
          // TLS handshake failed and `connect` threw.
        }

        XCTAssertTrue(delegate.wasInvoked)
      }
    #endif
  #endif

  // MARK: - _Delegate Auth Challenge Forwarding Tests

  // `URLAuthenticationChallenge`/`URLProtectionSpace` live in `FoundationNetworking` on Linux,
  // and `_Delegate`'s challenge-forwarding logic itself is a no-op there (see its `#if
  // canImport(FoundationNetworking)` guard in URLSessionWebSocket.swift) — these tests are
  // Apple-platforms-only.
  #if !canImport(FoundationNetworking)

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
        var receivedTask: URLSessionTask?
        func urlSession(
          _ session: URLSession,
          task: URLSessionTask,
          didReceive challenge: URLAuthenticationChallenge,
          completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
        ) {
          receivedChallenge = challenge
          receivedTask = task
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
      delegate.associatedTask.setValue(task)
      let challenge = makeChallenge()

      let expectation = expectation(description: "completion handler called")
      // The OS only ever calls this delegate's session-level method (see its doc comment) —
      // even when `wrappedDelegate` implements only the task-level one, that must still be
      // reached via `associatedTask`.
      delegate.urlSession(session, didReceive: challenge) { disposition, _ in
        XCTAssertEqual(disposition, .useCredential)
        expectation.fulfill()
      }

      wait(for: [expectation], timeout: 1)
      XCTAssertNotNil(wrappedDelegate.receivedChallenge)
      XCTAssertTrue(wrappedDelegate.receivedTask === task)
    }

    func testChallengeForwardedToSessionLevelWrappedDelegateWhenTaskLevelNotImplemented() {
      final class RecordingDelegate: NSObject, URLSessionDelegate {
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

      let wrappedDelegate = RecordingDelegate()
      let delegate = _Delegate(
        onComplete: nil,
        onWebSocketTaskOpened: nil,
        onWebSocketTaskClosed: nil,
        wrappedDelegate: wrappedDelegate
      )

      let session = URLSession(configuration: .default)
      let challenge = makeChallenge()

      let expectation = expectation(description: "completion handler called")
      delegate.urlSession(session, didReceive: challenge) { disposition, _ in
        XCTAssertEqual(disposition, .cancelAuthenticationChallenge)
        expectation.fulfill()
      }

      wait(for: [expectation], timeout: 1)
      XCTAssertNotNil(wrappedDelegate.receivedChallenge)
    }

    func testChallengeDefaultsToPerformDefaultHandlingWhenWrappedDelegateDoesNotImplementIt() {
      final class EmptyDelegate: NSObject, URLSessionDelegate {}

      let delegate = _Delegate(
        onComplete: nil,
        onWebSocketTaskOpened: nil,
        onWebSocketTaskClosed: nil,
        wrappedDelegate: EmptyDelegate()
      )

      let session = URLSession(configuration: .default)
      let challenge = makeChallenge()

      let expectation = expectation(description: "completion handler called")
      delegate.urlSession(session, didReceive: challenge) { disposition, credential in
        XCTAssertEqual(disposition, .performDefaultHandling)
        XCTAssertNil(credential)
        expectation.fulfill()
      }

      wait(for: [expectation], timeout: 1)
    }

    func testChallengeDefaultsToPerformDefaultHandlingWhenNoWrappedDelegate() {
      let delegate = _Delegate(
        onComplete: nil,
        onWebSocketTaskOpened: nil,
        onWebSocketTaskClosed: nil,
        wrappedDelegate: nil
      )

      let session = URLSession(configuration: .default)
      let challenge = makeChallenge()

      let expectation = expectation(description: "completion handler called")
      delegate.urlSession(session, didReceive: challenge) { disposition, credential in
        XCTAssertEqual(disposition, .performDefaultHandling)
        XCTAssertNil(credential)
        expectation.fulfill()
      }

      wait(for: [expectation], timeout: 1)
    }

  #endif
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

  #if os(macOS)
    import Security

    /// Generates a throwaway self-signed identity (private key + certificate) via the
    /// system `openssl` binary, then imports it into a `SecIdentity` for use with
    /// `NWProtocolTLS.Options`. macOS-only: relies on `Process` and `/usr/bin/openssl`,
    /// neither available on iOS/tvOS/watchOS simulator test destinations.
    private func makeSelfSignedIdentity() throws -> (identity: SecIdentity, certificateData: Data) {
      let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: tmpDir) }

      let keyURL = tmpDir.appendingPathComponent("key.pem")
      let certURL = tmpDir.appendingPathComponent("cert.pem")
      let p12URL = tmpDir.appendingPathComponent("identity.p12")
      let password = "test"

      func run(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
          throw WebSocketError.connection(
            message: "openssl \(arguments.first ?? "") failed",
            error: NSError(domain: "WebSocketTests", code: Int(process.terminationStatus))
          )
        }
      }

      try run([
        "req", "-x509", "-newkey", "rsa:2048", "-keyout", keyURL.path, "-out", certURL.path,
        "-days", "1", "-nodes", "-subj", "/CN=127.0.0.1",
      ])
      try run([
        "pkcs12", "-export", "-inkey", keyURL.path, "-in", certURL.path, "-out", p12URL.path,
        "-passout", "pass:\(password)",
      ])

      let p12Data = try Data(contentsOf: p12URL)
      var importResult: CFArray?
      let status = SecPKCS12Import(
        p12Data as CFData,
        [kSecImportExportPassphrase as String: password] as CFDictionary,
        &importResult
      )
      guard status == errSecSuccess,
        let items = importResult as? [[String: Any]],
        let identityRef = items.first?[kSecImportItemIdentity as String]
      else {
        throw WebSocketError.connection(
          message: "SecPKCS12Import failed",
          error: NSError(domain: "WebSocketTests", code: Int(status))
        )
      }
      let identity = identityRef as! SecIdentity

      var certificate: SecCertificate?
      SecIdentityCopyCertificate(identity, &certificate)
      guard let certificate else {
        throw WebSocketError.connection(
          message: "failed to extract certificate from identity",
          error: NSError(domain: "WebSocketTests", code: -1)
        )
      }

      return (identity, SecCertificateCopyData(certificate) as Data)
    }

    private final class LoopbackTLSWebSocketServer {
      private let listener: NWListener
      private let queue = DispatchQueue(label: "co.supabase.LoopbackTLSWebSocketServer")
      private var connections: [NWConnection] = []
      private var isStopped = false

      init(identity: SecIdentity) throws {
        let tlsOptions = NWProtocolTLS.Options()
        guard let secIdentity = sec_identity_create(identity) else {
          throw WebSocketError.connection(
            message: "sec_identity_create failed",
            error: NSError(domain: "LoopbackTLSWebSocketServer", code: -1)
          )
        }
        sec_protocol_options_set_local_identity(tlsOptions.securityProtocolOptions, secIdentity)

        let webSocketOptions = NWProtocolWebSocket.Options()
        webSocketOptions.autoReplyPing = true

        let parameters = NWParameters(tls: tlsOptions, tcp: .init())
        parameters.defaultProtocolStack.applicationProtocols.insert(webSocketOptions, at: 0)

        listener = try NWListener(using: parameters, on: .any)
      }

      func start() throws -> UInt16 {
        let ready = DispatchSemaphore(value: 0)

        listener.stateUpdateHandler = { state in
          switch state {
          case .ready, .failed:
            ready.signal()
          default:
            break
          }
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
            message: "loopback TLS server failed to start",
            error: NSError(domain: "LoopbackTLSWebSocketServer", code: -1)
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

    /// Session-level pinning delegate: accepts the server's certificate only if it
    /// matches `expectedCertificateData` byte-for-byte, otherwise cancels the challenge.
    /// This mirrors the shape of a real app's pinning delegate (see the `Usage` example
    /// in the design spec).
    private final class PinningSessionDelegate: NSObject, URLSessionDelegate {
      let expectedCertificateData: Data
      private let lockedWasInvoked = LockIsolated(false)
      var wasInvoked: Bool { lockedWasInvoked.value }

      init(expectedCertificateData: Data) {
        self.expectedCertificateData = expectedCertificateData
      }

      func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
      ) {
        lockedWasInvoked.setValue(true)

        guard
          challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
          let trust = challenge.protectionSpace.serverTrust,
          let serverCertificate = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first
        else {
          completionHandler(.cancelAuthenticationChallenge, nil)
          return
        }

        let serverCertificateData = SecCertificateCopyData(serverCertificate) as Data
        if serverCertificateData == expectedCertificateData {
          completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
          completionHandler(.cancelAuthenticationChallenge, nil)
        }
      }
    }

    /// Task-level pinning delegate: identical logic to `PinningSessionDelegate`, but
    /// implements only `URLSessionTaskDelegate`'s task-level challenge method (the modern,
    /// recommended form since iOS 15/macOS 12) rather than the classic session-level one.
    private final class PinningTaskDelegate: NSObject, URLSessionTaskDelegate {
      let expectedCertificateData: Data
      private let lockedWasInvoked = LockIsolated(false)
      var wasInvoked: Bool { lockedWasInvoked.value }

      init(expectedCertificateData: Data) {
        self.expectedCertificateData = expectedCertificateData
      }

      func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
      ) {
        lockedWasInvoked.setValue(true)

        guard
          challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
          let trust = challenge.protectionSpace.serverTrust,
          let serverCertificate = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first
        else {
          completionHandler(.cancelAuthenticationChallenge, nil)
          return
        }

        let serverCertificateData = SecCertificateCopyData(serverCertificate) as Data
        if serverCertificateData == expectedCertificateData {
          completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
          completionHandler(.cancelAuthenticationChallenge, nil)
        }
      }
    }
  #endif
#endif
