//
//  WebSocketTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 29/07/25.
//

import ConcurrencyExtras
import Foundation
import TestHelpers
import Testing

@testable import Realtime

// Cert-pinning tests generate self-signed identities via `SecPKCS12Import`, which is
// flaky when invoked concurrently (observed intermittent `errSecInternalComponent`/-26276
// failures under Swift Testing's default parallel execution). Serialize the suite so these
// identity-importing tests never overlap, mirroring the `.serialized` precedent used
// elsewhere for tests with process-global/shared-resource side effects.
@Suite(.serialized)
struct WebSocketTests {

  // MARK: - LegacyWebSocketEvent Tests

  @Test
  func webSocketEventEquality() {
    let textEvent1 = LegacyWebSocketEvent.text("hello")
    let textEvent2 = LegacyWebSocketEvent.text("hello")
    let textEvent3 = LegacyWebSocketEvent.text("world")

    #expect(textEvent1 == textEvent2)
    #expect(textEvent1 != textEvent3)

    let binaryData = Data([1, 2, 3])
    let binaryEvent1 = LegacyWebSocketEvent.binary(binaryData)
    let binaryEvent2 = LegacyWebSocketEvent.binary(binaryData)
    let binaryEvent3 = LegacyWebSocketEvent.binary(Data([4, 5, 6]))

    #expect(binaryEvent1 == binaryEvent2)
    #expect(binaryEvent1 != binaryEvent3)

    let closeEvent1 = LegacyWebSocketEvent.close(code: 1000, reason: "normal")
    let closeEvent2 = LegacyWebSocketEvent.close(code: 1000, reason: "normal")
    let closeEvent3 = LegacyWebSocketEvent.close(code: 1001, reason: "going away")

    #expect(closeEvent1 == closeEvent2)
    #expect(closeEvent1 != closeEvent3)
  }

  @Test
  func webSocketEventHashable() {
    let textEvent = LegacyWebSocketEvent.text("hello")
    let binaryEvent = LegacyWebSocketEvent.binary(Data([1, 2, 3]))
    let closeEvent = LegacyWebSocketEvent.close(code: 1000, reason: "normal")

    let events: Set<LegacyWebSocketEvent> = [textEvent, binaryEvent, closeEvent]
    #expect(events.count == 3)
  }

  @Test
  func webSocketEventPatternMatching() {
    let textEvent = LegacyWebSocketEvent.text("hello world")
    let binaryEvent = LegacyWebSocketEvent.binary(Data([1, 2, 3]))
    let closeEvent = LegacyWebSocketEvent.close(code: 1000, reason: "normal")

    switch textEvent {
    case .text(let message):
      #expect(message == "hello world")
    default:
      Issue.record("Expected text event")
    }

    switch binaryEvent {
    case .binary(let data):
      #expect(data == Data([1, 2, 3]))
    default:
      Issue.record("Expected binary event")
    }

    switch closeEvent {
    case .close(let code, let reason):
      #expect(code == 1000)
      #expect(reason == "normal")
    default:
      Issue.record("Expected close event")
    }
  }

  // MARK: - Connection Failure Tests

  // `URLProtocol` lives in `FoundationNetworking` on Linux, and swift-corelibs-foundation does
  // not route WebSocket tasks through custom `protocolClasses`, so this test is
  // Apple-platforms-only.
  #if !canImport(FoundationNetworking)
    @Test
    func connectFailureWrapsURLErrorAsConnectionKind() async {
      // A URLProtocol that fails any request it receives, so `connect` never reaches
      // the network and the failure is deterministic instead of depending on an
      // actual unreachable host.
      final class UnreachableProtocol: URLProtocol {
        override static func canInit(with request: URLRequest) -> Bool { true }
        override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
          client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
        }

        override func stopLoading() {}
      }

      let config = URLSessionConfiguration.ephemeral
      config.protocolClasses = [UnreachableProtocol.self]
      let session = URLSession(configuration: config)

      let url = URL(string: "ws://127.0.0.1:1")!

      do {
        _ = try await URLSessionWebSocket.connect(to: url, session: session)
        Issue.record("expected connect to throw")
      } catch let error as RealtimeError {
        #expect(error.kind == .transport)
        #expect(error.message.hasPrefix("connection ended unexpectedly"))
        #expect(error.underlyingError is URLError)
      } catch {
        Issue.record("Unexpected error: \(error)")
      }
    }

  #endif

  // MARK: - URLSessionWebSocket Lifecycle Tests

  #if canImport(Network)
    @Test
    func socketsDeallocateAfterClose() async throws {
      let server = try LoopbackWebSocketServer()
      let port = try server.start()
      defer { server.stop() }

      let url = URL(string: "ws://127.0.0.1:\(port)")!

      try await confirmation("sockets deallocated", expectedCount: 5) { deallocated in
        for _ in 0..<5 {
          let socket = try await URLSessionWebSocket.connect(to: url)
          objc_setAssociatedObject(
            socket,
            &deinitNotifierKey,
            DeinitNotifier { deallocated() },
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
          )
          socket.close(code: 1000, reason: nil)
        }

        // Give ARC a chance to actually run the deinits before the
        // confirmation scope closes and its count is checked. The iOS
        // Simulator runs noticeably slower than a native macOS host under
        // CI load, so this needs more margin than a quick local run suggests.
        try await Task.sleep(for: .seconds(1))
      }
    }

    @Test
    func connectAcceptsSessionWithADelegateAsATemplate() async throws {
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

    @Test
    func callerSuppliedSessionIsNeverUsedDirectlyOrInvalidated() async throws {
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

    /// Drives `_handleMessage` over a real connection: it is private and only ever reached from
    /// the `_task.receive()` loop, so a server that actually pushes frames is the only way in.
    ///
    /// Both frames matter. The second one can only arrive if handling the first re-armed the
    /// receive loop — if `_scheduleReceive()` stopped being called on the success path, the
    /// socket would go quiet after exactly one message and every other test here would still
    /// pass.
    @Test
    func deliversServerFramesAndKeepsListeningAfterEachOne() async throws {
      let server = try LoopbackWebSocketServer()
      let port = try server.start()
      defer { server.stop() }

      let url = URL(string: "ws://127.0.0.1:\(port)")!
      let socket = try await URLSessionWebSocket.connect(to: url)
      defer { socket.close(code: 1000, reason: nil) }

      let received = LockIsolated([LegacyWebSocketEvent]())
      let pump = Task { [socket] in
        for await event in socket.events {
          received.withValue { $0.append(event) }
        }
      }
      defer { pump.cancel() }

      server.send(text: "hello")
      #expect(await waitUntil { received.value.contains(.text("hello")) })

      let payload = Data([0x01, 0x02, 0x03])
      server.send(binary: payload)
      #expect(await waitUntil { received.value.contains(.binary(payload)) })
    }

    /// Pins the observable contract: nothing surfaces on `events` once the socket is closed, so
    /// a late frame can't reopen a stream a caller has already finished iterating.
    ///
    /// Deliberately not claimed as coverage of the `isClosed` guard in `_handleMessage`. Two
    /// mechanisms enforce this — that guard, and `events` having already finished — and removing
    /// either one on its own leaves this test green (verified by mutation). It pins the property,
    /// not the line.
    @Test
    func deliversNothingOnceTheSocketIsClosed() async throws {
      let server = try LoopbackWebSocketServer()
      let port = try server.start()
      defer { server.stop() }

      let url = URL(string: "ws://127.0.0.1:\(port)")!
      let socket = try await URLSessionWebSocket.connect(to: url)

      let received = LockIsolated([LegacyWebSocketEvent]())
      let pump = Task { [socket] in
        for await event in socket.events {
          received.withValue { $0.append(event) }
        }
      }
      defer { pump.cancel() }

      socket.close(code: 1000, reason: nil)
      #expect(await waitUntil { socket.isClosed })

      server.send(text: "too late")

      // Give the frame a chance to be mishandled before concluding it was dropped.
      try await Task.sleep(for: .milliseconds(200))
      #expect(received.value.contains(.text("too late")) == false)
    }

    #if os(macOS)
      @Test
      func selfSignedIdentityDoesNotPersistCertificate() throws {
        let (_, certificateData, cleanup) = try makeSelfSignedIdentity()
        defer { cleanup() }
        var keychain: SecKeychain?
        try #require(SecKeychainCopyDefault(&keychain) == errSecSuccess)
        let defaultKeychain = try #require(keychain)
        var result: CFTypeRef?
        let status = SecItemCopyMatching(
          [
            kSecClass: kSecClassCertificate,
            kSecMatchSearchList: [defaultKeychain],
            kSecMatchLimit: kSecMatchLimitAll,
            kSecReturnData: true,
          ] as CFDictionary,
          &result
        )
        #expect(status == errSecSuccess || status == errSecItemNotFound)
        let certificates = result as? [Data] ?? []
        #expect(!certificates.contains(certificateData))
      }

      @Test
      func certPinningAcceptsMatchingCertificate() async throws {
        let (identity, certificateData, cleanup) = try makeSelfSignedIdentity()
        defer { cleanup() }
        let server = try LoopbackTLSWebSocketServer(identity: identity)
        let port = try server.start()
        defer { server.stop() }

        let url = URL(string: "wss://127.0.0.1:\(port)")!
        let delegate = PinningSessionDelegate(expectedCertificateData: certificateData)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

        let socket = try await URLSessionWebSocket.connect(to: url, session: session)
        socket.close(code: 1000, reason: nil)

        #expect(delegate.wasInvoked)
      }

      @Test
      func certPinningRejectsMismatchedCertificate() async throws {
        let (identity, _, cleanup) = try makeSelfSignedIdentity()
        defer { cleanup() }
        let (_, wrongCertificateData, wrongCleanup) = try makeSelfSignedIdentity()
        defer { wrongCleanup() }
        let server = try LoopbackTLSWebSocketServer(identity: identity)
        let port = try server.start()
        defer { server.stop() }

        let url = URL(string: "wss://127.0.0.1:\(port)")!
        let delegate = PinningSessionDelegate(expectedCertificateData: wrongCertificateData)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

        do {
          _ = try await URLSessionWebSocket.connect(to: url, session: session)
          Issue.record("expected connection to fail due to certificate mismatch")
        } catch {
          // Expected: the pinning delegate rejected the server's certificate, so the
          // TLS handshake failed and `connect` threw.
        }

        #expect(delegate.wasInvoked)
      }

      @Test
      func certPinningAcceptsMatchingCertificateWithTaskLevelDelegate() async throws {
        let (identity, certificateData, cleanup) = try makeSelfSignedIdentity()
        defer { cleanup() }
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

        #expect(delegate.wasInvoked)
      }

      @Test
      func certPinningRejectsMismatchedCertificateWithTaskLevelDelegate() async throws {
        let (identity, _, cleanup) = try makeSelfSignedIdentity()
        defer { cleanup() }
        let (_, wrongCertificateData, wrongCleanup) = try makeSelfSignedIdentity()
        defer { wrongCleanup() }
        let server = try LoopbackTLSWebSocketServer(identity: identity)
        let port = try server.start()
        defer { server.stop() }

        let url = URL(string: "wss://127.0.0.1:\(port)")!
        let delegate = PinningTaskDelegate(expectedCertificateData: wrongCertificateData)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

        do {
          _ = try await URLSessionWebSocket.connect(to: url, session: session)
          Issue.record("expected connection to fail due to certificate mismatch")
        } catch {
          // Expected: the pinning delegate rejected the server's certificate, so the
          // TLS handshake failed and `connect` threw.
        }

        #expect(delegate.wasInvoked)
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

    @Test
    func challengeForwardedToTaskLevelWrappedDelegate() async {
      final class TaskDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
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

      // The OS only ever calls this delegate's session-level method (see its doc comment) —
      // even when `wrappedDelegate` implements only the task-level one, that must still be
      // reached via `associatedTask`.
      await confirmation("completion handler called") { completionCalled in
        delegate.urlSession(session, didReceive: challenge) { disposition, _ in
          #expect(disposition == .useCredential)
          completionCalled()
        }
      }
      #expect(wrappedDelegate.receivedChallenge != nil)
      #expect(wrappedDelegate.receivedTask === task)
    }

    @Test
    func challengeForwardedToSessionLevelWrappedDelegateWhenTaskLevelNotImplemented() async {
      final class RecordingDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
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

      await confirmation("completion handler called") { completionCalled in
        delegate.urlSession(session, didReceive: challenge) { disposition, _ in
          #expect(disposition == .cancelAuthenticationChallenge)
          completionCalled()
        }
      }
      #expect(wrappedDelegate.receivedChallenge != nil)
    }

    @Test
    func challengeDefaultsToPerformDefaultHandlingWhenWrappedDelegateDoesNotImplementIt() async {
      final class EmptyDelegate: NSObject, URLSessionDelegate {}

      let delegate = _Delegate(
        onComplete: nil,
        onWebSocketTaskOpened: nil,
        onWebSocketTaskClosed: nil,
        wrappedDelegate: EmptyDelegate()
      )

      let session = URLSession(configuration: .default)
      let challenge = makeChallenge()

      await confirmation("completion handler called") { completionCalled in
        delegate.urlSession(session, didReceive: challenge) { disposition, credential in
          #expect(disposition == .performDefaultHandling)
          #expect(credential == nil)
          completionCalled()
        }
      }
    }

    @Test
    func challengeDefaultsToPerformDefaultHandlingWhenNoWrappedDelegate() async {
      let delegate = _Delegate(
        onComplete: nil,
        onWebSocketTaskOpened: nil,
        onWebSocketTaskClosed: nil,
        wrappedDelegate: nil
      )

      let session = URLSession(configuration: .default)
      let challenge = makeChallenge()

      await confirmation("completion handler called") { completionCalled in
        delegate.urlSession(session, didReceive: challenge) { disposition, credential in
          #expect(disposition == .performDefaultHandling)
          #expect(credential == nil)
          completionCalled()
        }
      }
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

  #if os(macOS)
    import Security

    /// Generates a throwaway self-signed identity (private key + certificate) via the
    /// system `openssl` binary, then imports it into a `SecIdentity` for use with
    /// `NWProtocolTLS.Options`. macOS-only: relies on `Process` and `/usr/bin/openssl`,
    /// neither available on iOS/tvOS/watchOS simulator test destinations.
    private func makeSelfSignedIdentity() throws -> (
      identity: SecIdentity, certificateData: Data, cleanup: () -> Void
    ) {
      let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
      var temporaryKeychain: SecKeychain?
      let cleanup = {
        if let temporaryKeychain { SecKeychainDelete(temporaryKeychain) }
        try? FileManager.default.removeItem(at: tmpDir)
      }
      var succeeded = false
      defer { if !succeeded { cleanup() } }

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
          throw LoopbackError(message: "openssl \(arguments.first ?? "") failed")
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
      var options: [String: Any] = [kSecImportExportPassphrase as String: password]
      if #available(macOS 15, *) {
        options[kSecImportToMemoryOnly as String] = true
      } else {
        // Older macOS versions need an isolated keychain, deleted after the TLS test.
        let path = tmpDir.appendingPathComponent("test.keychain").path
        let status = password.withCString {
          SecKeychainCreate(path, UInt32(password.utf8.count), $0, false, nil, &temporaryKeychain)
        }
        guard status == errSecSuccess, let temporaryKeychain else {
          throw LoopbackError(message: "SecKeychainCreate failed: \(status)")
        }
        options[kSecImportExportKeychain as String] = temporaryKeychain
      }
      var importResult: CFArray?
      let status = SecPKCS12Import(p12Data as CFData, options as CFDictionary, &importResult)
      guard status == errSecSuccess,
        let items = importResult as? [[String: Any]],
        let identityRef = items.first?[kSecImportItemIdentity as String]
      else {
        throw LoopbackError(message: "SecPKCS12Import failed: \(status)")
      }
      let identity = identityRef as! SecIdentity

      var certificate: SecCertificate?
      SecIdentityCopyCertificate(identity, &certificate)
      guard let certificate else {
        throw LoopbackError(message: "failed to extract certificate from identity")
      }

      succeeded = true
      return (identity, SecCertificateCopyData(certificate) as Data, cleanup)
    }

    private final class LoopbackTLSWebSocketServer: @unchecked Sendable {
      private let listener: NWListener
      private let queue = DispatchQueue(label: "co.supabase.LoopbackTLSWebSocketServer")
      private var connections: [NWConnection] = []
      private var isStopped = false

      init(identity: SecIdentity) throws {
        let tlsOptions = NWProtocolTLS.Options()
        guard let secIdentity = sec_identity_create(identity) else {
          throw LoopbackError(message: "sec_identity_create failed")
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
          throw LoopbackError(message: "loopback TLS server failed to start")
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
