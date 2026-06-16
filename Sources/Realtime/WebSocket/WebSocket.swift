import Foundation

/// Represents events that can occur on a WebSocket connection.
enum WebSocketEvent: Sendable, Hashable {
  case text(String)
  case binary(Data)
  case close(code: Int?, reason: String)
}

/// Represents errors that can occur on a WebSocket connection.
enum WebSocketError: Error, LocalizedError {
  /// An error occurred while connecting to the peer.
  case connection(message: String, error: any Error)

  var errorDescription: String? {
    switch self {
    case .connection(let message, let error): "\(message) \(error.localizedDescription)"
    }
  }
}

/// The interface for WebSocket connection.
protocol WebSocket: Sendable, AnyObject {
  var closeCode: Int? { get }
  var closeReason: String? { get }

  /// Sends text data to the connected peer.
  /// - Parameter text: The text data to send.
  func send(_ text: String)

  /// Sends binary data to the connected peer.
  /// - Parameter binary: The binary data to send.
  func send(_ binary: Data)

  /// Closes the WebSocket connection and the ``events`` `AsyncStream`.
  ///
  /// Sends a Close frame to the peer. If the optional `code` and `reason` arguments are given, they will be included in the Close frame. If no `code` is set then the peer will see a 1005 status code. If no `reason` is set then the peer will not receive a reason string.
  /// - Parameters:
  ///   - code: The close code to send to the peer.
  ///   - reason: The reason for closing the connection.
  func close(code: Int?, reason: String?)

  /// Listen for event messages in the connection.
  var onEvent: (@Sendable (WebSocketEvent) -> Void)? { get set }

  /// An `AsyncStream` of ``WebSocketEvent`` received from the peer.
  ///
  /// Conformers must implement this as a protocol requirement (not just rely on
  /// the default extension) so that calls through `any WebSocket` dispatch to
  /// the version-guarded implementation and `onTermination` cannot nil a handler
  /// it no longer owns.
  var events: AsyncStream<WebSocketEvent> { get }

  /// The WebSocket subprotocol negotiated with the peer.
  ///
  /// Will be the empty string if no subprotocol was negotiated.
  ///
  /// See [RFC-6455 1.9](https://datatracker.ietf.org/doc/html/rfc6455#section-1.9).
  var `protocol`: String { get }

  /// Whether connection is closed.
  var isClosed: Bool { get }
}

extension WebSocket {
  /// Closes the WebSocket connection and the ``events`` `AsyncStream`.
  ///
  /// Sends a Close frame to the peer. If the optional `code` and `reason` arguments are given, they will be included in the Close frame. If no `code` is set then the peer will see a 1005 status code. If no `reason` is set then the peer will not receive a reason string.
  func close() {
    self.close(code: nil, reason: nil)
  }

  /// Default `events` implementation for test doubles and simple conformers.
  ///
  /// WARNING: Not safe for multi-read. If `events` is called a second time on
  /// the same conformer, the second call overwrites `onEvent` and the first
  /// call's `onTermination` will later nil out that live handler — silently
  /// dropping all subsequent frames (SDK-959). Production conformers MUST
  /// override this with a generation-guarded implementation (see `URLSessionWebSocket`).
  var events: AsyncStream<WebSocketEvent> {
    let (stream, continuation) = AsyncStream<WebSocketEvent>.makeStream()
    self.onEvent = { event in
      continuation.yield(event)
      if case .close = event {
        continuation.finish()
      }
    }
    continuation.onTermination = { _ in
      self.onEvent = nil
    }
    return stream
  }
}
