//
//  InMemoryTransport.swift
//  RealtimeV3Tests
//
//  Created by Guilherme Souza on 27/06/26.
//

import ConcurrencyExtras
import Foundation
import HTTPTypes

@testable import RealtimeV3

// MARK: - InMemoryTransport

/// An in-memory transport suitable for unit tests. Call `pair()` to obtain a
/// `(transport, server)` tuple: hand `transport` to the Realtime client and
/// use `server` to inject and observe frames.
///
/// **Reconnect behaviour:** `connect(to:headers:)` may be called more than once
/// (e.g., after a server-initiated close in reconnection tests). Each call
/// creates a fresh `InMemoryConnection` that shares the *same* `TransportServer`
/// streams, so the server can keep injecting/observing frames across reconnects.
actor InMemoryTransport: RealtimeTransport {
  // Expose connection metadata for assertion in later tasks.
  private(set) var lastConnectURL: URL?
  private(set) var lastConnectHeaders: HTTPFields?
  private(set) var connectCallCount: Int = 0

  private let server: TransportServer

  private init(server: TransportServer) {
    self.server = server
  }

  /// Creates a linked (transport, server) pair.
  nonisolated static func pair() -> (transport: InMemoryTransport, server: TransportServer) {
    let server = TransportServer()
    let transport = InMemoryTransport(server: server)
    return (transport, server)
  }

  nonisolated func connect(to url: URL, headers: HTTPFields) async throws -> any RealtimeConnection
  {
    await _connect(to: url, headers: headers)
  }

  private func _connect(to url: URL, headers: HTTPFields) -> any RealtimeConnection {
    lastConnectURL = url
    lastConnectHeaders = headers
    connectCallCount += 1
    // NOTE: All connections from repeated connect() calls share the same server streams
    // (reconnect support), so the server can keep injecting/observing frames across reconnects.
    return server.makeConnection()
  }
}

// MARK: - TransportServer

/// The server-side handle of an `InMemoryTransport` pair.
///
/// - `clientSentFrames`: yields every frame the Realtime client sends.
/// - `send(_:)`: injects a frame that the client's `frames` stream will yield.
/// - `closeFromServer(code:reason:)`: finishes both streams, simulating a
///   server-initiated close.
final class TransportServer: Sendable {
  // Frames the Realtime client sent → server observes.
  private let clientSentContinuation: LockIsolated<AsyncStream<TransportFrame>.Continuation?>
  let clientSentFrames: AsyncStream<TransportFrame>

  // Frames the server injected → client's connection.frames yields.
  private let serverToClientContinuation: LockIsolated<AsyncStream<TransportFrame>.Continuation?>
  // Stored so makeConnection() can hand it to each fresh InMemoryConnection.
  private let serverToClientStream: AsyncStream<TransportFrame>

  // Wraps serverToClientStream as AsyncThrowingStream for the connection.frames property.
  // We re-create a throwing wrapper each time makeConnection() is called.
  init() {
    let (clientSentStream, clientSentCont) = AsyncStream.makeStream(of: TransportFrame.self)
    let (serverToClientStr, serverToClientCont) = AsyncStream.makeStream(of: TransportFrame.self)
    self.clientSentFrames = clientSentStream
    self.clientSentContinuation = LockIsolated(clientSentCont)
    self.serverToClientStream = serverToClientStr
    self.serverToClientContinuation = LockIsolated(serverToClientCont)
  }

  /// Inject a frame that the connected client will receive on its `frames` stream.
  func send(_ frame: TransportFrame) {
    _ = serverToClientContinuation.withValue { $0?.yield(frame) }
  }

  /// Simulate a server-initiated close. Finishes both streams.
  func closeFromServer(code: Int, reason: String) {
    serverToClientContinuation.withValue { $0?.finish() }
    _ = clientSentContinuation.withValue { $0?.finish() }
  }

  /// Called by InMemoryTransport on each connect() to produce a fresh connection
  /// object. All connections share the same underlying streams, so the server
  /// keeps working across reconnects.
  fileprivate func makeConnection() -> InMemoryConnection {
    InMemoryConnection(
      serverToClientStream: serverToClientStream,
      clientSentContinuation: clientSentContinuation
    )
  }
}

// MARK: - InMemoryConnection (private)

/// A `RealtimeConnection` backed by the in-process streams managed by `TransportServer`.
private final class InMemoryConnection: RealtimeConnection, Sendable {
  let frames: AsyncThrowingStream<TransportFrame, any Error & Sendable>
  private let clientSentContinuation: LockIsolated<AsyncStream<TransportFrame>.Continuation?>
  private let bridgeTask: Task<Void, Never>

  init(
    serverToClientStream: AsyncStream<TransportFrame>,
    clientSentContinuation: LockIsolated<AsyncStream<TransportFrame>.Continuation?>
  ) {
    // Wrap the plain AsyncStream in AsyncThrowingStream as required by the protocol.
    // Use makeStream() so the bridging Task can be stored and cancelled on close().
    let (throwingStream, continuation) = AsyncThrowingStream<
      TransportFrame, any Error & Sendable
    >.makeStream()
    self.frames = throwingStream
    self.clientSentContinuation = clientSentContinuation
    self.bridgeTask = Task {
      for await frame in serverToClientStream {
        continuation.yield(frame)
      }
      continuation.finish()
    }
  }

  func send(_ frame: TransportFrame) async throws {
    _ = clientSentContinuation.withValue { $0?.yield(frame) }
  }

  func close(code: Int, reason: String) async {
    bridgeTask.cancel()
  }
}
