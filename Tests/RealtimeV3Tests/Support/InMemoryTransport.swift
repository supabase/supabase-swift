//
//  InMemoryTransport.swift
//  RealtimeV3Tests
//
//  Created by Guilherme Souza on 27/06/26.
//

import ConcurrencyExtras
import Foundation

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
  private(set) var lastConnectHeaders: [String: String]?
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

  nonisolated func connect(to url: URL, headers: [String: String]) async throws
    -> any RealtimeConnection
  {
    await _connect(to: url, headers: headers)
  }

  private func _connect(to url: URL, headers: [String: String]) -> any RealtimeConnection {
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
/// - `clientSentFrames`: yields every frame the Realtime client sends (across all connections).
/// - `send(_:)`: injects a frame that the currently-connected client will receive.
/// - `closeFromServer(code:reason:)`: finishes the current connection's streams, simulating a
///   server-initiated close. The next `makeConnection()` call (from a reconnect) establishes
///   a fresh server→client stream, so the server can keep injecting frames across reconnects.
///
/// ## Reconnect behaviour
/// `closeFromServer` only terminates the *current* connection's server→client stream.
/// `makeConnection()` always creates a fresh server→client stream pair, so each reconnect
/// gets a live stream. The client→server `clientSentFrames` stream is shared across all
/// connections so the test observer sees all frames from every connection attempt.
final class TransportServer: Sendable {
  // Frames the Realtime client sent → server observes (shared across reconnects).
  // NOTE: `closeFromServer` intentionally does NOT finish this stream so it survives
  // reconnects (the client→server channel is shared across all connection instances).
  // Consumers must iterate with `break` or task cancellation rather than awaiting
  // stream completion.
  private let clientSentContinuation: LockIsolated<AsyncStream<TransportFrame>.Continuation?>
  let clientSentFrames: AsyncStream<TransportFrame>

  // Active server→client stream continuation. Replaced on each makeConnection().
  // `closeFromServer` finishes this, and the next makeConnection() installs a new one.
  private let activeServerToClientContinuation:
    LockIsolated<
      AsyncStream<TransportFrame>.Continuation?
    >

  init() {
    let (clientSentStream, clientSentCont) = AsyncStream.makeStream(of: TransportFrame.self)
    self.clientSentFrames = clientSentStream
    self.clientSentContinuation = LockIsolated(clientSentCont)
    self.activeServerToClientContinuation = LockIsolated(nil)
  }

  /// Inject a frame that the connected client will receive on its `frames` stream.
  func send(_ frame: TransportFrame) {
    _ = activeServerToClientContinuation.withValue { $0?.yield(frame) }
  }

  /// Simulate a server-initiated close. Finishes the current server→client stream.
  /// The next `connect()` from the client will call `makeConnection()` which installs
  /// a fresh stream, allowing reconnect tests to work naturally.
  func closeFromServer(code: Int, reason: String) {
    activeServerToClientContinuation.withValue { $0?.finish() }
  }

  /// Called by InMemoryTransport on each connect() to produce a fresh connection object.
  /// Installs a new server→client continuation, replacing the previous (possibly finished) one.
  fileprivate func makeConnection() -> InMemoryConnection {
    // Create a fresh server→client stream for this connection.
    let (serverToClientStream, serverToClientCont) = AsyncStream.makeStream(
      of: TransportFrame.self
    )
    // Replace the active continuation so `send()` targets the new connection.
    activeServerToClientContinuation.withValue { $0 = serverToClientCont }

    return InMemoryConnection(
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
      // defer ensures the throwing-stream continuation is always finished, whether the
      // forwarding loop exits normally (end-of-stream) or because the task was cancelled
      // (by close()). Without this, a consumer awaiting `frames` could hang indefinitely.
      defer { continuation.finish() }
      for await frame in serverToClientStream {
        continuation.yield(frame)
      }
    }
  }

  func send(_ frame: TransportFrame) async throws {
    _ = clientSentContinuation.withValue { $0?.yield(frame) }
  }

  func close(code: Int, reason: String) async {
    bridgeTask.cancel()
  }
}
