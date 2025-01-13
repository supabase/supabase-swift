import ConcurrencyExtras
import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// A WebSocket connection that uses `URLSession`.
final class URLSessionWebSocket: WebSocket {
  private init(
    _task: URLSessionWebSocketTask,
    _protocol: String
  ) {
    self._task = _task
    self._protocol = _protocol

    _scheduleReceive()
  }

  /// Create a new WebSocket connection.
  /// - Parameters:
  ///   - url: The URL to connect to.
  ///   - protocols: An optional array of protocols to negotiate with the server.
  ///   - configuration: An optional `URLSessionConfiguration` to use for the connection.
  /// - Returns: A `URLSessionWebSocket` instance.
  /// - Throws: An error if the connection fails.
  static func connect(
    to url: URL,
    protocols: [String]? = nil,
    configuration: URLSessionConfiguration? = nil
  ) async throws -> URLSessionWebSocket {
    guard url.scheme == "ws" || url.scheme == "wss" else {
      preconditionFailure("only ws: and wss: schemes are supported")
    }

    struct MutableState {
      var continuation: CheckedContinuation<URLSessionWebSocket, any Error>!
      var webSocket: URLSessionWebSocket?
    }

    let mutableState = LockIsolated(MutableState())

    let session = URLSession.sessionWithConfiguration(
      configuration ?? .default,
      onComplete: { session, task, error in
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
              code: 1006, reason: Data("abnormal close".utf8))
          } else if let error {
            $0.continuation.resume(
              throwing: WebSocketError.connection(
                message: "connection ended unexpectedly", error: error))
          } else {
            // `onWebSocketTaskOpened` should have been called and resumed continuation.
            // So either there was an error creating the connection or a logic error.
            assertionFailure(
              "expected an error or `onWebSocketTaskOpened` to have been called first")
          }
        }
      },
      onWebSocketTaskOpened: { session, task, `protocol` in
        mutableState.withValue {
          $0.webSocket = URLSessionWebSocket(_task: task, _protocol: `protocol` ?? "")
          $0.continuation.resume(returning: $0.webSocket!)
        }
      },
      onWebSocketTaskClosed: { session, task, code, reason in
        mutableState.withValue {
          assert($0.webSocket != nil, "connection should exist by this time")
          $0.webSocket!._connectionClosed(code: code, reason: reason)
        }
      }
    )

    session.webSocketTask(with: url, protocols: protocols ?? []).resume()
    return try await withCheckedThrowingContinuation { continuation in
      mutableState.withValue {
        $0.continuation = continuation
      }
    }
  }

  let _task: URLSessionWebSocketTask
  let _protocol: String

  struct MutableState {
    var isClosed = false
    var onEvent: (@Sendable (WebSocketEvent) -> Void)?

    var closeCode: Int?
    var closeReason: String?
  }

  let mutableState = LockIsolated(MutableState())

  var closeCode: Int? {
    mutableState.value.closeCode
  }

  var closeReason: String? {
    mutableState.value.closeReason
  }

  var isClosed: Bool {
    mutableState.value.isClosed
  }

  private func _handleMessage(_ value: URLSessionWebSocketTask.Message) {
    guard !isClosed else { return }

    let event =
      switch value {
      case .string(let string):
        WebSocketEvent.text(string)
      case .data(let data):
        WebSocketEvent.binary(data)
      @unknown default:
        fatalError("Unsupported message.")
      }
    _trigger(event)
    _scheduleReceive()
  }

  private func _scheduleReceive() {
    _task.receive { [weak self] result in
      switch result {
      case .success(let value): self?._handleMessage(value)
      case .failure(let error): self?._closeConnectionWithError(error)
      }
    }
  }

  private func _closeConnectionWithError(_ error: any Error) {
    let nsError = error as NSError
    if nsError.domain == NSPOSIXErrorDomain && nsError.code == 57 {
      // Socket is not connected.
      // onWebsocketTaskClosed/onComplete will be invoked and may indicate a close code.
      return
    }
    let (code, reason) =
      switch (nsError.domain, nsError.code) {
      case (NSPOSIXErrorDomain, 100):
        (1002, nsError.localizedDescription)
      case (_, _):
        (1006, nsError.localizedDescription)
      }
    _task.cancel()
    _connectionClosed(code: code, reason: Data(reason.utf8))
  }

  private func _connectionClosed(code: Int?, reason: Data?) {
    guard !isClosed else { return }

    let closeReason = reason.map { String(decoding: $0, as: UTF8.self) } ?? ""
    _trigger(.close(code: code, reason: closeReason))
  }

  func send(_ text: String) {
    guard !isClosed else {
      return
    }

    _task.send(.string(text)) { [weak self] error in
      if let error {
        self?._closeConnectionWithError(error)
      }
    }
  }

  var onEvent: (@Sendable (WebSocketEvent) -> Void)? {
    get { mutableState.value.onEvent }
    set { mutableState.withValue { $0.onEvent = newValue } }
  }

  private func _trigger(_ event: WebSocketEvent) {
    mutableState.withValue {
      $0.onEvent?(event)

      if case .close(let code, let reason) = event {
        $0.onEvent = nil
        $0.isClosed = true
        $0.closeCode = code
        $0.closeReason = reason
      }
    }
  }

  func send(_ binary: Data) {
    guard !isClosed else {
      return
    }

    _task.send(.data(binary)) { [weak self] error in
      if let error {
        self?._closeConnectionWithError(error)
      }
    }
  }

  func close(code: Int?, reason: String?) {
    guard !isClosed else {
      return
    }

    if code != nil, code != 1000, !(code! >= 3000 && code! <= 4999) {
      preconditionFailure(
        "Invalid argument: \(code!), close code must be 1000 or in the range 3000-4999")
    }

    if reason != nil, reason!.utf8.count > 123 {
      preconditionFailure("reason must be <= 123 bytes long and encoded as UTF-8")
    }

    mutableState.withValue {
      if !$0.isClosed {
        if code != nil {
          let reason = reason ?? ""
          _task.cancel(
            with: URLSessionWebSocketTask.CloseCode(rawValue: code!)!,
            reason: Data(reason.utf8)
          )
        } else {
          _task.cancel()
        }
      }
    }
  }

  var `protocol`: String { _protocol }
}

extension URLSession {
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

final class _Delegate: NSObject, URLSessionDelegate, URLSessionDataDelegate, URLSessionTaskDelegate,
  URLSessionWebSocketDelegate
{
  let onComplete: (@Sendable (URLSession, URLSessionTask, (any Error)?) -> Void)?
  let onWebSocketTaskOpened: (@Sendable (URLSession, URLSessionWebSocketTask, String?) -> Void)?
  let onWebSocketTaskClosed: (@Sendable (URLSession, URLSessionWebSocketTask, Int?, Data?) -> Void)?

  init(
    onComplete: (@Sendable (URLSession, URLSessionTask, (any Error)?) -> Void)?,
    onWebSocketTaskOpened: (
      @Sendable (URLSession, URLSessionWebSocketTask, String?) -> Void
    )?,
    onWebSocketTaskClosed: (
      @Sendable (URLSession, URLSessionWebSocketTask, Int?, Data?) -> Void
    )?
  ) {
    self.onComplete = onComplete
    self.onWebSocketTaskOpened = onWebSocketTaskOpened
    self.onWebSocketTaskClosed = onWebSocketTaskClosed
  }

  func urlSession(
    _ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?
  ) {
    onComplete?(session, task, error)
  }

  func urlSession(
    _ session: URLSession, webSocketTask: URLSessionWebSocketTask,
    didOpenWithProtocol protocol: String?
  ) {
    onWebSocketTaskOpened?(session, webSocketTask, `protocol`)
  }

  func urlSession(
    _ session: URLSession, webSocketTask: URLSessionWebSocketTask,
    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?
  ) {
    onWebSocketTaskClosed?(session, webSocketTask, closeCode.rawValue, reason)
  }
}
