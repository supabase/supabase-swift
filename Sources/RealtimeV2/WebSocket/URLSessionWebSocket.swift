import ConcurrencyExtras
import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// A WebSocket connection implementation using `URLSession`.
///
/// This class provides a WebSocket connection built on top of `URLSessionWebSocketTask`.
/// It handles connection lifecycle, message sending/receiving, and proper cleanup.
///
/// ## Thread Safety
/// This class is thread-safe and can be used from multiple concurrent contexts.
/// All operations are protected by internal synchronization mechanisms.
///
/// ## Connection Management
/// The connection is established asynchronously using the `connect(to:protocols:headers:session:)` method.
/// Once connected, you can send text/binary messages and listen for events through the `events` stream.
///
/// ## Error Handling
/// Network errors are automatically handled and converted to appropriate WebSocket close codes.
/// The connection will be closed gracefully when errors occur, with proper cleanup of resources.
final class URLSessionWebSocket: WebSocket {
  /// Private initializer for creating a WebSocket instance.
  /// - Parameters:
  ///   - _task: The underlying `URLSessionWebSocketTask` for this connection.
  ///   - _protocol: The negotiated WebSocket subprotocol, empty string if none.
  ///   - ownsSession: Whether this instance created `session` itself (a dedicated internal
  ///     session) as opposed to being handed one by the caller. Only owned sessions are
  ///     invalidated on close — invalidating a caller-supplied session (e.g. one also used
  ///     for Auth/PostgREST/Storage) would break all of its other, unrelated usage.
  private init(
    _task: URLSessionWebSocketTask,
    _protocol: String,
    session: URLSession,
    ownsSession: Bool
  ) {
    self._task = _task
    self._protocol = _protocol
    self.session = session
    self.ownsSession = ownsSession

    (events, eventsContinuation) = AsyncStream.makeStream()

    _scheduleReceive()
  }

  /// Creates and establishes a new WebSocket connection.
  ///
  /// This method asynchronously connects to the specified WebSocket URL and returns
  /// a fully initialized `URLSessionWebSocket` instance ready for use.
  ///
  /// - Parameters:
  ///   - url: The WebSocket URL to connect to. Must use `ws://` or `wss://` scheme.
  ///   - protocols: Optional array of WebSocket subprotocols to negotiate with the server.
  ///   - headers: Optional HTTP headers to include in the WebSocket upgrade request.
  ///              These are set on the URLRequest rather than on URLSessionConfiguration's
  ///              httpAdditionalHeaders, which can interfere with the WebSocket upgrade handshake.
  ///   - session: The `URLSession` used to create the WebSocket task, when explicitly
  ///             provided (i.e. not `.shared`). Its `delegate`'s auth-challenge callbacks
  ///             (if any) are forwarded to, enabling certificate pinning and other
  ///             server-trust customization. When left at the default `.shared`, `connect`
  ///             builds its own dedicated internal session instead (unaffected by
  ///             process-wide `URLSession` state), matching this method's original behavior.
  /// - Returns: A connected `URLSessionWebSocket` instance.
  /// - Throws: `WebSocketError.connection` if the connection fails or times out.
  static func connect(
    to url: URL,
    protocols: [String]? = nil,
    headers: [String: String]? = nil,
    session: URLSession = .shared
  ) async throws -> URLSessionWebSocket {
    guard url.scheme == "ws" || url.scheme == "wss" else {
      preconditionFailure("only ws: and wss: schemes are supported")
    }

    struct MutableState {
      var continuation: CheckedContinuation<URLSessionWebSocket, any Error>!
      var webSocket: URLSessionWebSocket?
    }

    let mutableState = LockIsolated(MutableState())

    #if canImport(FoundationNetworking)
      // Linux always builds a dedicated internal session (see below) — it always owns it.
      let ownsSession = true
    #else
      // A dedicated internal session is built (and owned) exactly when the caller didn't
      // supply their own — see the matching branch below for the full rationale.
      let ownsSession = session === URLSession.shared
    #endif

    let onComplete: @Sendable (URLSession, URLSessionTask, (any Error)?) -> Void = {
      session, task, error in
      mutableState.withValue {
        if let webSocket = $0.webSocket {
          // There are three possibilities here:
          // 1. the peer sent a close Frame, `onWebSocketTaskClosed` was already
          //    called and `_connectionClosed` is a no-op.
          // 2. we sent a close Frame (through `close()`) and `_connectionClosed`
          //    is a no-op.
          // 3. an error occurred (e.g. network failure) and `_connectionClosed`
          //    will signal that and close `event`.
          webSocket._connectionClosed(
            code: 1006,
            reason: Data("abnormal close".utf8)
          )
        } else if let error {
          $0.continuation.resume(
            throwing: WebSocketError.connection(
              message: "connection ended unexpectedly",
              error: error
            )
          )
        } else {
          // `onWebSocketTaskOpened` should have been called and resumed continuation.
          // So either there was an error creating the connection or a logic error.
          assertionFailure(
            "expected an error or `onWebSocketTaskOpened` to have been called first"
          )
        }
      }
    }
    let onWebSocketTaskOpened: @Sendable (URLSession, URLSessionWebSocketTask, String?) -> Void = {
      session, task, `protocol` in
      mutableState.withValue {
        $0.webSocket = URLSessionWebSocket(
          _task: task, _protocol: `protocol` ?? "", session: session, ownsSession: ownsSession)
        $0.continuation.resume(returning: $0.webSocket!)
      }
    }
    let onWebSocketTaskClosed:
      @Sendable (URLSession, URLSessionWebSocketTask, Int?, Data?) -> Void =
        { session, task, code, reason in
          mutableState.withValue {
            assert($0.webSocket != nil, "connection should exist by this time")
            $0.webSocket!._connectionClosed(code: code, reason: reason)
          }
        }

    func makeTask(on session: URLSession) -> URLSessionWebSocketTask {
      if let headers, !headers.isEmpty {
        // Use URLRequest to set headers instead of httpAdditionalHeaders on the
        // URLSessionConfiguration. Setting httpAdditionalHeaders can interfere with
        // the WebSocket upgrade handshake on iOS, causing -1005 errors.
        var request = URLRequest(url: url)
        for (key, value) in headers {
          request.setValue(value, forHTTPHeaderField: key)
        }
        // session.webSocketTask(with: URLRequest) doesn't accept a protocols
        // parameter, so set the Sec-WebSocket-Protocol header manually.
        if let protocols, !protocols.isEmpty {
          request.setValue(
            protocols.joined(separator: ", "), forHTTPHeaderField: "Sec-WebSocket-Protocol")
        }
        return session.webSocketTask(with: request)
      } else {
        return session.webSocketTask(with: url, protocols: protocols ?? [])
      }
    }

    func makeDedicatedSession() -> URLSession {
      URLSession.sessionWithConfiguration(
        session.configuration,
        onComplete: onComplete,
        onWebSocketTaskOpened: onWebSocketTaskOpened,
        onWebSocketTaskClosed: onWebSocketTaskClosed
      )
    }

    let task: URLSessionWebSocketTask
    #if canImport(FoundationNetworking)
      // swift-corelibs-foundation doesn't support per-task `URLSessionTask.delegate`
      // (needed to forward auth challenges without hijacking the caller's session-level
      // delegate). Fall back to a dedicated session with `_Delegate` attached at the
      // session level, matching this method's pre-existing behavior. Certificate-pinning
      // delegate forwarding via `session.delegate` is unavailable on Linux (build-only,
      // not a production-supported platform for this package).
      task = makeTask(on: makeDedicatedSession())
    #else
      if ownsSession {
        // No caller-supplied session: preserve pre-existing behavior exactly — build a
        // dedicated internal session isolated from process-wide `URLSession` state (e.g.
        // an app's own globally-registered `URLProtocol`, used for mocking or ad-hoc
        // interception), rather than silently routing the WebSocket handshake through
        // `.shared`. `.shared` is also `RealtimeClientOptions.session`'s own default and
        // the sentinel `SupabaseClient` checks against when propagating `global.session`
        // — this identity check is consistent with both: pinning only activates when a
        // caller has actually opted in by supplying their own session.
        task = makeTask(on: makeDedicatedSession())
      } else {
        // Caller explicitly supplied their own session (e.g. one with a pinning delegate)
        // — use it directly and forward its delegate's auth-challenge callback via a
        // per-task delegate, while keeping WebSocket lifecycle callbacks internal.
        task = makeTask(on: session)
        task.delegate = _Delegate(
          onComplete: onComplete,
          onWebSocketTaskOpened: onWebSocketTaskOpened,
          onWebSocketTaskClosed: onWebSocketTaskClosed,
          wrappedDelegate: session.delegate
        )
      }
    #endif

    return try await withCheckedThrowingContinuation { continuation in
      mutableState.withValue {
        $0.continuation = continuation
      }
      task.resume()
    }
  }

  /// The underlying URLSession WebSocket task.
  let _task: URLSessionWebSocketTask
  /// The negotiated WebSocket subprotocol.
  let _protocol: String
  private let session: URLSession
  private let ownsSession: Bool

  /// Thread-safe mutable state for the WebSocket connection.
  struct MutableState {
    /// Whether the connection has been closed.
    var isClosed = false
    /// The close code received when connection was closed.
    var closeCode: Int?
    /// The close reason received when connection was closed.
    var closeReason: String?
  }

  /// Lock-isolated mutable state to ensure thread safety.
  let mutableState = LockIsolated(MutableState())

  /// The close code received when the connection was closed, if any.
  var closeCode: Int? {
    mutableState.value.closeCode
  }

  /// The close reason received when the connection was closed, if any.
  var closeReason: String? {
    mutableState.value.closeReason
  }

  /// Whether the WebSocket connection is closed.
  var isClosed: Bool {
    mutableState.value.isClosed
  }

  let events: AsyncStream<WebSocketEvent>
  let eventsContinuation: AsyncStream<WebSocketEvent>.Continuation

  /// Handles incoming WebSocket messages and converts them to events.
  /// - Parameter value: The message received from the WebSocket.
  private func _handleMessage(_ value: URLSessionWebSocketTask.Message) {
    guard !isClosed else { return }

    let event: WebSocketEvent
    switch value {
    case .string(let text):
      event = .text(text)
    case .data(let data):
      event = .binary(data)
    @unknown default:
      // Handle unknown message types gracefully by closing the connection
      _closeConnectionWithError(
        WebSocketError.connection(
          message: "Received unsupported message type",
          error: NSError(
            domain: "WebSocketError",
            code: 1002,
            userInfo: [NSLocalizedDescriptionKey: "Unsupported message type"]
          )
        )
      )
      return
    }
    _trigger(event)
    _scheduleReceive()
  }

  /// Schedules the next message receive operation.
  /// This method continuously listens for incoming messages until the connection is closed.
  private func _scheduleReceive() {
    Task {
      let result = await Result { try await _task.receive() }
      switch result {
      case .success(let value):
        _handleMessage(value)
      case .failure(let error):
        _closeConnectionWithError(error)
      }
    }
  }

  /// Closes the connection due to an error and maps the error to appropriate WebSocket close codes.
  /// - Parameter error: The error that caused the connection to close.
  private func _closeConnectionWithError(_ error: any Error) {
    let nsError = error as NSError

    // Handle socket not connected error - delegate callbacks will handle this
    if nsError.domain == NSPOSIXErrorDomain && nsError.code == 57 {
      // Socket is not connected.
      // onWebsocketTaskClosed/onComplete will be invoked and may indicate a close code.
      return
    }

    // Map errors to appropriate WebSocket close codes per RFC 6455
    let (code, reason): (Int, String) = {
      switch (nsError.domain, nsError.code) {
      case (NSPOSIXErrorDomain, 100):
        // Network protocol error
        return (1002, nsError.localizedDescription)
      case (NSURLErrorDomain, NSURLErrorTimedOut):
        // Connection timeout
        return (1006, "Connection timed out")
      case (NSURLErrorDomain, NSURLErrorNetworkConnectionLost):
        // Network connection lost
        return (1006, "Network connection lost")
      case (NSURLErrorDomain, NSURLErrorNotConnectedToInternet):
        // No internet connection
        return (1006, "No internet connection")
      default:
        // Abnormal closure for other errors
        return (1006, nsError.localizedDescription)
      }
    }()

    _task.cancel()
    _connectionClosed(code: code, reason: Data(reason.utf8))
  }

  /// Handles the connection being closed and triggers the close event.
  /// - Parameters:
  ///   - code: The WebSocket close code, if available.
  ///   - reason: The close reason data, if available.
  private func _connectionClosed(code: Int?, reason: Data?) {
    guard !isClosed else { return }

    let closeReason = reason.map { String(decoding: $0, as: UTF8.self) } ?? ""
    _trigger(.close(code: code, reason: closeReason))
  }

  /// Sends a text message to the connected peer.
  /// - Parameter text: The text message to send.
  ///
  /// This method is non-blocking and will return immediately. If the connection
  /// is closed, the message will be silently dropped. Any errors during sending
  /// will cause the connection to be closed with an appropriate error code.
  func send(_ text: String) {
    guard !isClosed else {
      return
    }

    Task {
      do {
        try await _task.send(.string(text))
      } catch {
        _closeConnectionWithError(error)
      }
    }
  }

  /// Triggers a WebSocket event and updates internal state if needed.
  /// - Parameter event: The event to trigger.
  private func _trigger(_ event: WebSocketEvent) {
    let shouldInvalidate = mutableState.withValue {
      eventsContinuation.yield(event)

      // Update state when connection closes
      if case .close(let code, let reason) = event {
        let wasClosed = $0.isClosed
        $0.isClosed = true
        $0.closeCode = code
        $0.closeReason = reason
        return !wasClosed
      }
      return false
    }

    // Only invalidate a session this instance created itself. Invalidating a
    // caller-supplied session (e.g. one also used for Auth/PostgREST/Storage) would break
    // all of its other, unrelated usage.
    if shouldInvalidate && ownsSession {
      session.finishTasksAndInvalidate()
    }
  }

  /// Sends binary data to the connected peer.
  /// - Parameter binary: The binary data to send.
  ///
  /// This method is non-blocking and will return immediately. If the connection
  /// is closed, the message will be silently dropped. Any errors during sending
  /// will cause the connection to be closed with an appropriate error code.
  func send(_ binary: Data) {
    guard !isClosed else {
      return
    }

    Task {
      do {
        try await _task.send(.data(binary))
      } catch {
        _closeConnectionWithError(error)
      }
    }
  }

  /// Closes the WebSocket connection gracefully.
  ///
  /// Sends a close frame to the peer with the specified code and reason.
  /// Valid close codes are 1000 (normal closure) or in the range 3000-4999 (application-specific).
  ///
  /// - Parameters:
  ///   - code: Optional close code. Must be 1000 or in range 3000-4999. Defaults to normal closure.
  ///   - reason: Optional reason string. Must be ≤ 123 bytes when UTF-8 encoded.
  ///
  /// - Note: If the connection is already closed, this method has no effect.
  func close(code: Int?, reason: String?) {
    guard !isClosed else {
      return
    }

    // Validate close code per RFC 6455
    if let code = code, code != 1000, !(code >= 3000 && code <= 4999) {
      preconditionFailure(
        "Invalid close code: \(code). Must be 1000 or in range 3000-4999"
      )
    }

    // Validate reason length per RFC 6455
    if let reason = reason, reason.utf8.count > 123 {
      preconditionFailure("Close reason must be ≤ 123 bytes when UTF-8 encoded")
    }

    mutableState.withValue {
      guard !$0.isClosed else { return }

      if let code = code {
        let closeReason = reason ?? ""
        _task.cancel(
          with: URLSessionWebSocketTask.CloseCode(rawValue: code)!,
          reason: Data(closeReason.utf8)
        )
      } else {
        _task.cancel()
      }
    }
  }

  /// The WebSocket subprotocol negotiated with the peer.
  ///
  /// Returns an empty string if no subprotocol was negotiated during the handshake.
  /// See [RFC 6455 Section 1.9](https://datatracker.ietf.org/doc/html/rfc6455#section-1.9) for details.
  var `protocol`: String { _protocol }
}

// MARK: - URLSession Extension

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
      nil
  ) -> URLSession {
    let queue = OperationQueue()
    queue.maxConcurrentOperationCount = 1

    let hasDelegate =
      onComplete != nil || onWebSocketTaskOpened != nil || onWebSocketTaskClosed != nil

    if hasDelegate {
      return URLSession(
        configuration: configuration,
        delegate: _Delegate(
          onComplete: onComplete,
          onWebSocketTaskOpened: onWebSocketTaskOpened,
          onWebSocketTaskClosed: onWebSocketTaskClosed
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

  /// Forwards the task-level auth challenge to `wrappedDelegate`, trying its task-level
  /// implementation first, then falling back to its session-level implementation, then to
  /// default handling. Always calls `completionHandler` exactly once.
  ///
  /// The `#selector`/`responds(to:)`-based dispatch below requires the Objective-C runtime,
  /// unavailable in swift-corelibs-foundation (Linux) — guarded accordingly. `connect(session:)`
  /// never populates `wrappedDelegate` on Linux (see its `#if canImport(FoundationNetworking)`
  /// branch), so this always falls through to default handling there regardless.
  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
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

      let taskLevelSelector = #selector(
        (any URLSessionTaskDelegate).urlSession(_:task:didReceive:completionHandler:))
      if let taskDelegate = wrappedDelegate as? any URLSessionTaskDelegate,
        wrappedDelegate.responds(to: taskLevelSelector)
      {
        taskDelegate.urlSession?(
          session, task: task, didReceive: challenge, completionHandler: completionHandler)
        return
      }

      let sessionLevelSelector = #selector(
        (any URLSessionDelegate).urlSession(_:didReceive:completionHandler:))
      if wrappedDelegate.responds(to: sessionLevelSelector) {
        wrappedDelegate.urlSession?(
          session, didReceive: challenge, completionHandler: completionHandler)
        return
      }

      completionHandler(.performDefaultHandling, nil)
    #endif
  }
}
