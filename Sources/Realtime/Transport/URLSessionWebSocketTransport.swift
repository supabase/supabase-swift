//
//  URLSessionWebSocketTransport.swift
//  Realtime
//
//  Created by Guilherme Souza on 06/10/26.
//

import ConcurrencyExtras
package import Foundation
package import HTTPTypes

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
    // Darwin imports `CloseCode` as a non-exhaustive `NS_ENUM`, so 4001 goes out as 4001.
    // swift-corelibs-foundation makes it a closed Swift enum, so 3000...4999 convert to `nil`
    // there and the frame goes out with no status rather than a wrong one.
    if let closeCode = URLSessionWebSocketTask.CloseCode(rawValue: code.rawValue) {
      task.cancel(with: closeCode, reason: reason.map { Data($0.utf8) })
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

extension URLSession {
  /// Creates a URLSession with WebSocket delegate callbacks.
  ///
  /// This factory method creates a URLSession configured with the specified delegate callbacks
  /// for handling WebSocket lifecycle events. The session uses a dedicated operation queue
  /// with maximum concurrency of 1 to ensure proper sequencing of delegate callbacks.
  ///
  /// - Parameters:
  ///   - configuration: The URLSession configuration to use.
  ///   - onComplete: Optional callback when a task completes (with or without error).
  ///   - onWebSocketTaskOpened: Optional callback when a WebSocket connection opens successfully.
  ///   - onWebSocketTaskClosed: Optional callback when a WebSocket connection closes.
  /// - Returns: A configured URLSession instance.
  static func sessionWithConfiguration(
    _ configuration: URLSessionConfiguration,
    onComplete: (@Sendable (URLSession, URLSessionTask, (any Error)?) -> Void)? = nil,
    onWebSocketTaskOpened: (@Sendable (URLSession, URLSessionWebSocketTask, String?) -> Void)? =
      nil,
    onWebSocketTaskClosed: (@Sendable (URLSession, URLSessionWebSocketTask, Int?, Data?) -> Void)? =
      nil,
    wrappedDelegate: (any URLSessionDelegate)? = nil
  ) -> URLSession {
    let queue = OperationQueue()
    queue.maxConcurrentOperationCount = 1

    let hasDelegate =
      onComplete != nil || onWebSocketTaskOpened != nil || onWebSocketTaskClosed != nil
      || wrappedDelegate != nil

    if hasDelegate {
      return URLSession(
        configuration: configuration,
        delegate: _Delegate(
          onComplete: onComplete,
          onWebSocketTaskOpened: onWebSocketTaskOpened,
          onWebSocketTaskClosed: onWebSocketTaskClosed,
          wrappedDelegate: wrappedDelegate
        ),
        delegateQueue: queue
      )
    } else {
      return URLSession(configuration: configuration)
    }
  }
}

// MARK: - Private Delegate

/// Internal URLSession delegate for handling WebSocket events.
///
/// This delegate handles the various WebSocket lifecycle events and forwards them
/// to the appropriate callbacks provided during URLSession creation. It also forwards
/// TLS/auth-challenge callbacks to a wrapped delegate (typically the caller's own
/// session delegate), so apps can pin certificates on the Realtime WebSocket connection
/// using the same `URLSessionDelegate` they already use elsewhere.
final class _Delegate: NSObject, URLSessionDelegate, URLSessionDataDelegate, URLSessionTaskDelegate,
  URLSessionWebSocketDelegate
{
  /// Callback for task completion events.
  let onComplete: (@Sendable (URLSession, URLSessionTask, (any Error)?) -> Void)?
  /// Callback for WebSocket connection opened events.
  let onWebSocketTaskOpened: (@Sendable (URLSession, URLSessionWebSocketTask, String?) -> Void)?
  /// Callback for WebSocket connection closed events.
  let onWebSocketTaskClosed: (@Sendable (URLSession, URLSessionWebSocketTask, Int?, Data?) -> Void)?
  /// The delegate captured from the caller's own `URLSession` (if any), consulted for
  /// auth-challenge forwarding only. Read-only after `init`; only ever invoked from the
  /// URLSession delegate queue, the same way `URLSession` itself would call it.
  private let wrappedDelegate: (any URLSessionDelegate)?
  /// The task `connect` creates for this connection, set once right after creation (the
  /// delegate must exist before the task can be created, since the session needs a
  /// delegate at construction time). Used to forward auth challenges to `wrappedDelegate`'s
  /// task-level implementation with a real task reference, even though the challenge itself
  /// arrives through this delegate's session-level callback.
  let associatedTask = LockIsolated<URLSessionTask?>(nil)

  init(
    onComplete: (@Sendable (URLSession, URLSessionTask, (any Error)?) -> Void)?,
    onWebSocketTaskOpened: (
      @Sendable (URLSession, URLSessionWebSocketTask, String?) -> Void
    )?,
    onWebSocketTaskClosed: (
      @Sendable (URLSession, URLSessionWebSocketTask, Int?, Data?) -> Void
    )?,
    wrappedDelegate: (any URLSessionDelegate)? = nil
  ) {
    self.onComplete = onComplete
    self.onWebSocketTaskOpened = onWebSocketTaskOpened
    self.onWebSocketTaskClosed = onWebSocketTaskClosed
    self.wrappedDelegate = wrappedDelegate
  }

  /// Called when a task completes, with or without error.
  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: (any Error)?
  ) {
    onComplete?(session, task, error)
  }

  /// Called when a WebSocket connection is successfully established.
  func urlSession(
    _ session: URLSession,
    webSocketTask: URLSessionWebSocketTask,
    didOpenWithProtocol protocol: String?
  ) {
    onWebSocketTaskOpened?(session, webSocketTask, `protocol`)
  }

  /// Called when a WebSocket connection is closed.
  func urlSession(
    _ session: URLSession,
    webSocketTask: URLSessionWebSocketTask,
    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
    reason: Data?
  ) {
    onWebSocketTaskClosed?(session, webSocketTask, closeCode.rawValue, reason)
  }

  /// Forwards the auth challenge to `wrappedDelegate`, trying its task-level implementation
  /// first (the modern, recommended form since iOS 15/macOS 12), then falling back to its
  /// session-level implementation, then to default handling. Always calls
  /// `completionHandler` exactly once.
  ///
  /// This delegate is only ever attached at the session level (see `connect`), so the OS
  /// always calls this method — never the task-level overload — even when `wrappedDelegate`
  /// itself only implements the task-level one. `associatedTask` supplies a real task
  /// reference for that forwarding attempt despite this method itself not receiving one.
  ///
  /// The `#selector`/`responds(to:)` checks require the Objective-C runtime, unavailable in
  /// swift-corelibs-foundation (Linux) — guarded accordingly. `wrappedDelegate` may still be
  /// populated on Linux (`connect` doesn't special-case it), but this method ignores it there
  /// and always falls through to default handling: certificate pinning isn't supported on
  /// Linux (build-only, not a production-supported platform for this package).
  func urlSession(
    _ session: URLSession,
    didReceive challenge: URLAuthenticationChallenge,
    completionHandler:
      @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) ->
      Void
  ) {
    #if canImport(FoundationNetworking)
      completionHandler(.performDefaultHandling, nil)
    #else
      guard let wrappedDelegate else {
        completionHandler(.performDefaultHandling, nil)
        return
      }

      if let task = associatedTask.value,
        let taskDelegate = wrappedDelegate as? any URLSessionTaskDelegate,
        wrappedDelegate.responds(
          to: #selector(
            (any URLSessionTaskDelegate).urlSession(_:task:didReceive:completionHandler:)))
      {
        taskDelegate.urlSession?(
          session, task: task, didReceive: challenge, completionHandler: completionHandler)
        return
      }

      if wrappedDelegate.responds(
        to: #selector((any URLSessionDelegate).urlSession(_:didReceive:completionHandler:)))
      {
        wrappedDelegate.urlSession?(
          session, didReceive: challenge, completionHandler: completionHandler)
        return
      }

      completionHandler(.performDefaultHandling, nil)
    #endif
  }
}
