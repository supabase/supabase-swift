//
//  URLSessionTransport.swift
//  RealtimeV3
//
//  Created by Guilherme Souza on 29/06/26.
//

import ConcurrencyExtras
import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

// MARK: - URLSessionTransport

/// A production `RealtimeTransport` backed by `URLSessionWebSocketTask`.
///
/// Inject a custom `URLSession` for testing. The default session is configured
/// with `.default` and a delegate that bridges the WebSocket lifecycle events.
///
/// Headers are set on the `URLRequest` rather than on
/// `URLSessionConfiguration.httpAdditionalHeaders`, which can interfere with
/// the WebSocket upgrade on iOS (see `URLSessionWebSocket` in the v2 transport).
public struct URLSessionTransport: RealtimeTransport {
  private let session: URLSession?

  /// Creates a transport that uses the shared `URLSession.shared`.
  public init() {
    self.session = nil
  }

  /// Creates a transport backed by `session`. Use this to inject a custom session
  /// (e.g. one with a mock delegate) in tests.
  public init(session: URLSession) {
    self.session = session
  }

  public func connect(to url: URL, headers: [String: String]) async throws
    -> any RealtimeConnection
  {
    let effectiveSession: URLSession
    if let session {
      effectiveSession = session
    } else {
      effectiveSession = URLSession.shared
    }

    var request = URLRequest(url: url)
    for (key, value) in headers {
      request.setValue(value, forHTTPHeaderField: key)
    }

    let task = effectiveSession.webSocketTask(with: request)
    let connection = URLSessionConnection(task: task)
    task.resume()
    return connection
  }
}

// MARK: - URLSessionConnection

/// A `RealtimeConnection` backed by a `URLSessionWebSocketTask`.
///
/// The `frames` stream is driven by a background receive loop that calls
/// `task.receive()` in a tight `while` loop. The loop terminates when the task
/// is cancelled, when the WebSocket is closed, or when `receive()` throws.
private final class URLSessionConnection: RealtimeConnection, @unchecked Sendable {
  let frames: AsyncThrowingStream<TransportFrame, any Error & Sendable>
  private let continuation: AsyncThrowingStream<TransportFrame, any Error & Sendable>.Continuation
  private let task: URLSessionWebSocketTask
  private let receiveLoop: Task<Void, Never>
  private let _isClosed = LockIsolated(false)

  init(task: URLSessionWebSocketTask) {
    self.task = task
    let (stream, cont) = AsyncThrowingStream<TransportFrame, any Error & Sendable>.makeStream()
    self.frames = stream
    self.continuation = cont

    // Capture continuation in a local to avoid capturing self before init finishes.
    let capturedTask = task
    let capturedCont = cont
    self.receiveLoop = Task {
      await URLSessionConnection.runReceiveLoop(task: capturedTask, continuation: capturedCont)
    }
  }

  /// Drives the receive loop without capturing `self`, avoiding init-before-capture issues.
  private static func runReceiveLoop(
    task: URLSessionWebSocketTask,
    continuation: AsyncThrowingStream<TransportFrame, any Error & Sendable>.Continuation
  ) async {
    while !Task.isCancelled {
      do {
        let message = try await task.receive()
        switch message {
        case .string(let text):
          continuation.yield(.text(text))
        case .data(let data):
          continuation.yield(.binary(data))
        @unknown default:
          break
        }
      } catch {
        // receive() threw — connection closed or cancelled. Finish the stream.
        continuation.finish(throwing: error)
        return
      }
    }
    continuation.finish()
  }

  func send(_ frame: TransportFrame) async throws {
    guard !_isClosed.value else { return }
    switch frame {
    case .text(let text):
      try await task.send(.string(text))
    case .binary(let data):
      try await task.send(.data(data))
    }
  }

  func close(code: Int, reason: String) async {
    _isClosed.setValue(true)
    receiveLoop.cancel()
    // URLSessionWebSocketTask accepts close codes 1000 or 3000–4999.
    // Map any invalid code to 1000 to avoid a precondition failure.
    let validCode: URLSessionWebSocketTask.CloseCode
    if code == 1000 {
      validCode = .normalClosure
    } else if code >= 3000, code <= 4999,
      let c = URLSessionWebSocketTask.CloseCode(rawValue: code)
    {
      validCode = c
    } else {
      validCode = .normalClosure
    }
    task.cancel(with: validCode, reason: Data(reason.utf8))
  }
}
