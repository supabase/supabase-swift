//
//  URLSessionWebSocketTransport.swift
//  Realtime
//
//  Created by Guilherme Souza on 06/10/26.
//

import ConcurrencyExtras
package import Foundation
package import HTTPTypes
import IssueReporting

#if canImport(FoundationNetworking)
  package import FoundationNetworking
#endif

/// The default ``WebSocketTransport``, built on `URLSessionWebSocketTask`.
///
/// Every connection gets its own `URLSession` copied from `configuration`, so process-wide
/// `URLSession` state never reaches the socket and the session can be invalidated on close.
/// `delegate` is consulted for TLS challenges only, which is how an app pins certificates.
package struct URLSessionWebSocketTransport: WebSocketTransport, @unchecked Sendable {
  let configuration: URLSessionConfiguration
  let delegate: (any URLSessionDelegate)?

  package init(
    configuration: URLSessionConfiguration = .default,
    delegate: (any URLSessionDelegate)? = nil
  ) {
    self.configuration = configuration
    self.delegate = delegate
  }

  package func connect(to url: URL, headerFields: HTTPFields) async throws
    -> any WebSocketConnection
  {
    guard url.scheme == "ws" || url.scheme == "wss" else {
      throw RealtimeError(
        kind: .transport,
        message: "only ws: and wss: schemes are supported, got \(url.scheme ?? "no scheme").",
        isRetryable: false,
        underlyingError: URLError(.unsupportedURL)
      )
    }

    struct Handshake {
      var continuation: CheckedContinuation<URLSessionWebSocketConnection, any Error>?
      var connection: URLSessionWebSocketConnection?
    }
    let handshake = LockIsolated(Handshake())

    // Each callback computes what to do under the lock and runs it after releasing it: resuming
    // a continuation can take the runtime's task-status lock, and holding ours at the same time
    // inverts the order cancellation takes (supabase/supabase-swift#1154).
    let session = URLSession.sessionWithConfiguration(
      configuration,
      onComplete: { session, task, error in
        let afterUnlock: @Sendable () -> Void = handshake.withValue { state in
          if let connection = state.connection {
            return { connection.connectionClosed(code: nil, reason: nil, abnormal: true) }
          }
          session.finishTasksAndInvalidate()
          guard let continuation = state.continuation else { return {} }
          state.continuation = nil
          return { continuation.resume(throwing: Self.connectError(task: task, error: error)) }
        }
        afterUnlock()
      },
      onWebSocketTaskOpened: { session, task, _ in
        let (connection, continuation) = handshake.withValue { state in
          let connection = URLSessionWebSocketConnection(task: task, session: session)
          state.connection = connection
          defer { state.continuation = nil }
          return (connection, state.continuation)
        }
        continuation?.resume(returning: connection)
      },
      onWebSocketTaskClosed: { _, _, code, reason in
        let connection = handshake.withValue(\.connection)
        connection?.connectionClosed(
          code: code.map(WebSocketCloseCode.init(rawValue:)),
          reason: reason.map { String(decoding: $0, as: UTF8.self) },
          abnormal: false
        )
      },
      wrappedDelegate: delegate
    )

    // Headers go on the request, not `httpAdditionalHeaders`: the latter can break the upgrade
    // handshake on iOS with a -1005 error.
    var request = URLRequest(url: url)
    for field in headerFields {
      request.setValue(field.value, forHTTPHeaderField: field.name.rawName)
    }
    let task = session.webSocketTask(with: request)
    // The receive limit. URLSession's 1 MiB default would drop the socket on a large row; the
    // server never sends a frame over its own 5,000,000-byte cap.
    task.maximumMessageSize = 5_000_000
    (session.delegate as? _Delegate)?.associatedTask.setValue(task)

    let connection = try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        handshake.withValue { $0.continuation = continuation }
        task.resume()
      }
    } onCancel: {
      task.cancel()
    }
    return connection
  }

  /// Maps a failed handshake to the error `connect` throws.
  static func connectError(task: URLSessionTask, error: (any Error)?) -> any Error {
    if (error as? URLError)?.code == .cancelled {
      return CancellationError()
    }
    if let response = task.response as? HTTPURLResponse, response.statusCode != 101 {
      return RealtimeError.upgradeFailed(status: response.statusCode, underlyingError: error)
    }
    return RealtimeError(
      kind: .transport,
      message: "connection ended unexpectedly \(error?.localizedDescription ?? "")",
      underlyingError: error
    )
  }

  /// Maps a transport error onto the close code and reason to report, per RFC 6455.
  ///
  /// Returns `nil` for `ENOTCONN`: the socket is already gone and the delegate will report the
  /// peer's own close code, so synthesizing one here would race it.
  static func closeFrame(for error: any Error) -> (code: Int, reason: String)? {
    let nsError = error as NSError

    // errno values differ per platform (ENOTCONN is 57 on Darwin, 107 on Linux), so the
    // platform constants are matched rather than the numbers. `POSIXErrorCode` would read
    // better but Android's Foundation does not vend it.
    switch (nsError.domain, nsError.code) {
    case (NSPOSIXErrorDomain, Int(ENOTCONN)):
      return nil
    case (NSPOSIXErrorDomain, Int(EPROTO)):
      return (1002, nsError.localizedDescription)
    case (NSURLErrorDomain, NSURLErrorTimedOut):
      return (1006, "Connection timed out")
    case (NSURLErrorDomain, NSURLErrorNetworkConnectionLost):
      return (1006, "Network connection lost")
    case (NSURLErrorDomain, NSURLErrorNotConnectedToInternet):
      return (1006, "No internet connection")
    default:
      return (1006, nsError.localizedDescription)
    }
  }

  /// Returns `code` if RFC 6455 §7.4 allows an endpoint to send it, otherwise `nil`.
  ///
  /// Pure so it can be tested directly: the caller reports the rejection, and driving
  /// `reportIssue` from a `@Test` segfaults under `xcodebuild test` (SDK-435).
  static func validatedCloseCode(_ code: Int?) -> Int? {
    guard let code else { return nil }
    let sendable = [1000...1003, 1007...1011, 3000...4999]
    return sendable.contains { $0.contains(code) } ? code : nil
  }

  /// Returns `reason` truncated on whole characters to the 123-byte limit of RFC 6455 §5.5.
  static func validatedCloseReason(_ reason: String?) -> String? {
    guard let reason, reason.utf8.count > 123 else { return reason }

    var truncated = ""
    for character in reason {
      guard truncated.utf8.count + character.utf8.count <= 123 else { break }
      truncated.append(character)
    }
    return truncated
  }
}

/// One `URLSessionWebSocketTask`, read by a single receive loop and written by awaited sends.
final class URLSessionWebSocketConnection: WebSocketConnection {
  let events: AsyncStream<WebSocketEvent>
  private let continuation: AsyncStream<WebSocketEvent>.Continuation
  private let task: URLSessionWebSocketTask
  private let session: URLSession
  private let isClosed = LockIsolated(false)
  /// Owns the connection until the final `.closed` event: it holds `self` so a caller that
  /// drops its reference without closing still gets the socket drained and torn down.
  private let receiveTask = LockIsolated<Task<Void, Never>?>(nil)

  init(task: URLSessionWebSocketTask, session: URLSession) {
    self.task = task
    self.session = session
    // Unbounded on purpose: this stream carries protocol frames, and dropping a `phx_reply`
    // leaves the push waiting on it hanging until it times out.
    (events, continuation) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
    receiveTask.setValue(Task { await receiveLoop() })
  }

  private func receiveLoop() async {
    while !isClosed.value {
      do {
        switch try await task.receive() {
        case .string(let text): continuation.yield(.frame(.text(text)))
        case .data(let data): continuation.yield(.frame(.binary(data)))
        @unknown default: closeConnection(with: RealtimeError.decoding("unsupported message type"))
        }
      } catch {
        closeConnection(with: error)
        return
      }
    }
  }

  func send(_ frame: WebSocketFrame) async throws {
    guard !isClosed.value else {
      throw RealtimeError(kind: .notConnected, message: "WebSocket is closed.")
    }
    do {
      switch frame {
      case .text(let text): try await task.send(.string(text))
      case .binary(let data): try await task.send(.data(data))
      }
    } catch {
      closeConnection(with: error)
      throw RealtimeError(
        kind: .transport, message: "send failed: \(error.localizedDescription)",
        underlyingError: error)
    }
  }

  func close(code: WebSocketCloseCode, reason: String?) async {
    guard !isClosed.value else { return }

    let validatedCode = URLSessionWebSocketTransport.validatedCloseCode(code.rawValue)
    if validatedCode == nil {
      reportIssue(
        "Invalid close code \(code.rawValue). Must be 1000 or in 3000...4999. Closing without a code."
      )
    }
    let validatedReason = URLSessionWebSocketTransport.validatedCloseReason(reason)
    if let reason, validatedReason != reason {
      reportIssue(
        "Close reason is \(reason.utf8.count) bytes, over the 123-byte limit. Truncating it.")
    }

    // Darwin imports `CloseCode` as a non-exhaustive `NS_ENUM`, so 4001 goes out as 4001.
    // swift-corelibs-foundation makes it a closed Swift enum, so 3000...4999 convert to `nil`
    // there and the frame goes out with no status rather than a wrong one.
    let closeCode = validatedCode.flatMap(URLSessionWebSocketTask.CloseCode.init(rawValue:))
    if validatedCode != nil, closeCode == nil {
      reportIssue(
        "Close code \(code.rawValue) is not representable on this platform. Closing without a code."
      )
    }
    if let closeCode {
      task.cancel(with: closeCode, reason: Data((validatedReason ?? "").utf8))
    } else {
      task.cancel()
    }
  }

  private func closeConnection(with error: any Error) {
    guard let frame = URLSessionWebSocketTransport.closeFrame(for: error) else { return }
    task.cancel()
    connectionClosed(
      code: WebSocketCloseCode(rawValue: frame.code), reason: frame.reason, abnormal: false)
  }

  /// Emits the final `.closed` event once. `abnormal` is the task completing without a close
  /// frame, after a close from either side would already have reported its own code.
  func connectionClosed(code: WebSocketCloseCode?, reason: String?, abnormal: Bool) {
    let wasClosed = isClosed.withValue { closed in
      defer { closed = true }
      return closed
    }
    guard !wasClosed else { return }

    if abnormal {
      continuation.yield(.closed(code: .abnormalClosure, reason: "abnormal close"))
    } else {
      continuation.yield(.closed(code: code, reason: reason))
    }
    continuation.finish()
    session.finishTasksAndInvalidate()
    receiveTask.value?.cancel()
  }
}
