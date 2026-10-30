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

@Suite(.serialized)
struct WebSocketTests {

  #if !canImport(FoundationNetworking)
    @Test
    func connectFailureWrapsURLErrorAsConnectionKind() async {
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
      let transport = URLSessionWebSocketTransport(configuration: config)

      let url = URL(string: "ws://127.0.0.1:1")!

      do {
        _ = try await transport.connect(to: url, headerFields: [:])
        Issue.record("expected connect to throw")
      } catch let error as RealtimeError {
        #expect(error.kind == .transport)
        #expect(error.message.hasPrefix("connection ended unexpectedly"))
        #expect(error.underlyingError is URLError)
      } catch {
        Issue.record("Unexpected error: \(error)")
      }
    }

    /// A delegate that rejects a pinned certificate cancels the challenge, so the handshake
    /// fails with `URLError.cancelled`. That is a failed connect the client must retry, not a
    /// cancellation of the caller's task.
    @Test
    func cancelledHandshakeIsARetryableTransportError() async {
      final class CancelledProtocol: URLProtocol {
        override static func canInit(with request: URLRequest) -> Bool { true }
        override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
          client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
        }

        override func stopLoading() {}
      }

      let config = URLSessionConfiguration.ephemeral
      config.protocolClasses = [CancelledProtocol.self]
      let transport = URLSessionWebSocketTransport(configuration: config)

      let error = await #expect(throws: RealtimeError.self) {
        _ = try await transport.connect(to: URL(string: "ws://127.0.0.1:1")!, headerFields: [:])
      }
      #expect(error?.kind == .transport)
      #expect(error?.isRetryable == true)
      #expect((error?.underlyingError as? URLError)?.code == .cancelled)
    }

  #endif

  #if canImport(Network)
    @Test
    func socketsDeallocateAfterClose() async throws {
      let server = try LoopbackWebSocketServer()
      let port = try server.start()
      defer { server.stop() }

      let url = URL(string: "ws://127.0.0.1:\(port)")!

      try await confirmation("sockets deallocated", expectedCount: 5) { deallocated in
        for _ in 0..<5 {
          let connection = try await URLSessionWebSocketTransport()
            .connect(to: url, headerFields: [:])
          objc_setAssociatedObject(
            connection as AnyObject,
            &deinitNotifierKey,
            DeinitNotifier { deallocated() },
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
          )
          connection.close(code: .normalClosure, reason: nil)
        }

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

      let transport = URLSessionWebSocketTransport(
        configuration: session.configuration, delegate: session.delegate)

      let connection = try await transport.connect(to: url, headerFields: [:])
      connection.close(code: .normalClosure, reason: nil)
    }

    @Test
    func callerSuppliedSessionIsNeverUsedDirectlyOrInvalidated() async throws {
      let server = try LoopbackWebSocketServer()
      let port = try server.start()
      defer { server.stop() }

      let url = URL(string: "ws://127.0.0.1:\(port)")!
      let session = URLSession(configuration: .default)

      let transport = URLSessionWebSocketTransport(
        configuration: session.configuration, delegate: session.delegate)

      let first = try await transport.connect(to: url, headerFields: [:])
      first.close(code: .normalClosure, reason: nil)

      // `finishTasksAndInvalidate()` invalidates asynchronously via a delegate callback;
      // give it time to take effect before checking whether the session still works.
      try await Task.sleep(for: .milliseconds(200))

      let second = try await transport.connect(to: url, headerFields: [:])
      second.close(code: .normalClosure, reason: nil)
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

        let connection = try await URLSessionWebSocketTransport(
          configuration: session.configuration, delegate: session.delegate
        ).connect(to: url, headerFields: [:])
        connection.close(code: .normalClosure, reason: nil)

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
          _ = try await URLSessionWebSocketTransport(
            configuration: session.configuration, delegate: session.delegate
          ).connect(to: url, headerFields: [:])
          Issue.record("expected connection to fail due to certificate mismatch")
        } catch let error as RealtimeError {
          #expect(error.kind == .transport)
          #expect(error.isRetryable)
        } catch {
          Issue.record("Unexpected error: \(error)")
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
        let delegate = PinningTaskDelegate(expectedCertificateData: certificateData)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

        let connection = try await URLSessionWebSocketTransport(
          configuration: session.configuration, delegate: session.delegate
        ).connect(to: url, headerFields: [:])
        connection.close(code: .normalClosure, reason: nil)

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
          _ = try await URLSessionWebSocketTransport(
            configuration: session.configuration, delegate: session.delegate
          ).connect(to: url, headerFields: [:])
          Issue.record("expected connection to fail due to certificate mismatch")
        } catch let error as RealtimeError {
          #expect(error.kind == .transport)
          #expect(error.isRetryable)
        } catch {
          Issue.record("Unexpected error: \(error)")
        }

        #expect(delegate.wasInvoked)
      }
    #endif
  #endif

  #if !canImport(FoundationNetworking)

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
