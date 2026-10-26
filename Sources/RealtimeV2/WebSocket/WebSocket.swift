public import Foundation

// The public names carry a `Realtime` prefix so they do not collide with `WebSocket` types from
// other libraries in apps that import both. The module keeps using the short names internally.
typealias WebSocket = RealtimeWebSocket
typealias WebSocketEvent = RealtimeWebSocketEvent

/// Represents events that can occur on a WebSocket connection.
public enum RealtimeWebSocketEvent: Sendable, Hashable {
  /// A text message from the peer.
  case text(String)
  /// A binary message from the peer.
  case binary(Data)
  /// The connection closed, with the close code and reason the peer sent, if any.
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
///
/// Conform to this protocol to give ``RealtimeClientV2`` a WebSocket implementation of your own
/// through ``RealtimeClientOptions/transport``.
public protocol RealtimeWebSocket: Sendable, AnyObject {
  /// The close code of the connection, or `nil` while it is open.
  var closeCode: Int? { get }

  /// The close reason of the connection, or `nil` while it is open.
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

  /// An `AsyncStream` of ``RealtimeWebSocketEvent`` received from the peer.
  var events: AsyncStream<RealtimeWebSocketEvent> { get }

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
