//
//  InMemoryTransport.swift
//  _Realtime
//
//  Created by Guilherme Souza on 24/04/25.
//

import Foundation

/// A paired in-memory transport for deterministic tests. No real I/O.
///
/// Usage:
/// ```swift
/// let (transport, server) = InMemoryTransport.pair()
/// let realtime = Realtime(url: testURL, apiKey: .literal("key"), transport: transport)
/// ```
public final class InMemoryTransport: RealtimeTransport, @unchecked Sendable {
  // @unchecked Sendable: all stored properties are `let` immutable streams/continuations.
  // server -> client
  private let serverToClientStream: AsyncThrowingStream<TransportFrame, any Error>
  private let serverToClientCont: AsyncThrowingStream<TransportFrame, any Error>.Continuation
  // client -> server
  private let clientToServerStream: AsyncThrowingStream<TransportFrame, any Error>
  private let clientToServerCont: AsyncThrowingStream<TransportFrame, any Error>.Continuation

  private init() {
    let (s2cStream, s2cCont) = AsyncThrowingStream<TransportFrame, any Error>.makeStream()
    let (c2sStream, c2sCont) = AsyncThrowingStream<TransportFrame, any Error>.makeStream()
    self.serverToClientStream = s2cStream
    self.serverToClientCont = s2cCont
    self.clientToServerStream = c2sStream
    self.clientToServerCont = c2sCont
  }

  public static func pair() -> (client: InMemoryTransport, server: InMemoryServer) {
    let t = InMemoryTransport()
    let s = InMemoryServer(
      receivedFrames: t.clientToServerStream,
      sendContinuation: t.serverToClientCont
    )
    return (t, s)
  }

  public func connect(to url: URL, headers: [String: String]) async throws -> any RealtimeConnection {
    InMemoryConnection(
      inbound: serverToClientStream,
      outbound: clientToServerCont
    )
  }
}

/// The server side of an `InMemoryTransport` pair.
///
/// **API contract — choose one per test:**
/// - Use `receivedFrames` when you need a continuous stream of client frames (e.g., auto-reply loop in a `Task`).
/// - Use `receive()` when you need to await exactly one frame at a time.
///
/// Do NOT use both APIs concurrently on the same `InMemoryServer` instance — they share the same
/// underlying `AsyncThrowingStream` buffer and concurrent use will cause frames to be dropped.
public final class InMemoryServer: Sendable {
  // All stored properties are `let` — Sendable is safe.
  private let _receivedFrames: AsyncThrowingStream<TransportFrame, any Error>
  private let sendContinuation: AsyncThrowingStream<TransportFrame, any Error>.Continuation

  /// Stream of frames the client has sent, for tests that need to inspect them.
  public var receivedFrames: AsyncThrowingStream<TransportFrame, any Error> { _receivedFrames }

  init(
    receivedFrames: AsyncThrowingStream<TransportFrame, any Error>,
    sendContinuation: AsyncThrowingStream<TransportFrame, any Error>.Continuation
  ) {
    self._receivedFrames = receivedFrames
    self.sendContinuation = sendContinuation
  }

  /// Awaits the next frame the client sent.
  public func receive() async -> TransportFrame? {
    try? await _receivedFrames.first(where: { _ in true })
  }

  /// Push a frame to the client.
  public func send(_ frame: TransportFrame) async {
    sendContinuation.yield(frame)
  }

  /// Simulate server-initiated close.
  ///
  /// The `code` and `reason` parameters are accepted for API compatibility but are not propagated —
  /// the client always sees a `URLError(.networkConnectionLost)`.
  public func close(code: Int = 1000, reason: String = "") {
    sendContinuation.finish(throwing: URLError(.networkConnectionLost))
  }
}

private struct InMemoryConnection: RealtimeConnection, Sendable {
  let frames: AsyncThrowingStream<TransportFrame, any Error>
  private let outbound: AsyncThrowingStream<TransportFrame, any Error>.Continuation

  init(
    inbound: AsyncThrowingStream<TransportFrame, any Error>,
    outbound: AsyncThrowingStream<TransportFrame, any Error>.Continuation
  ) {
    self.frames = inbound
    self.outbound = outbound
  }

  func send(_ frame: TransportFrame) async throws {
    outbound.yield(frame)
  }

  func close(code: Int, reason: String) async {
    outbound.finish()
  }
}
