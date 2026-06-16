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

  /// An `AsyncStream` of ``WebSocketEvent`` received from the peer.
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

}
