//
//  WebSocketTransport.swift
//  Realtime
//
//  Created by Guilherme Souza on 06/10/26.
//

public import Foundation
public import HTTPTypes

/// Opens WebSocket connections for the Realtime client.
///
/// The client owns one connection at a time and reads it through ``WebSocketConnection``. The
/// default is ``URLSessionWebSocketTransport``. Set ``RealtimeClientOptions/webSocketTransport`` to
/// use another WebSocket stack.
public protocol WebSocketTransport: Sendable {
  /// Performs the HTTP upgrade and returns the open connection.
  ///
  /// Throw a ``RealtimeError``. Its ``RealtimeError/isRetryable`` tells the client whether to back
  /// off and try again (network failure, 429, 5xx) or to stop (401, 403, 404); any other error
  /// counts as a retryable transport failure. Rethrow `CancellationError` when the calling task is
  /// cancelled mid-handshake.
  ///
  /// - Parameters:
  ///   - url: The `ws` or `wss` URL to open.
  ///   - headerFields: The header fields of the upgrade request.
  func connect(to url: URL, headerFields: HTTPFields) async throws -> any WebSocketConnection
}

/// One open WebSocket connection.
public protocol WebSocketConnection: Sendable {
  /// Every frame the peer sends, then exactly one ``WebSocketEvent/closed(code:reason:)``,
  /// after which the stream finishes. A close is an event, never a thrown error.
  var events: AsyncStream<WebSocketEvent> { get }

  /// Sends one frame and returns once the transport has accepted it. Frames go out in call
  /// order, so the client can rely on `phx_join` reaching the wire before anything sent after.
  func send(_ frame: WebSocketFrame) async throws

  /// Starts a graceful close. The `.closed` event on ``events`` reports completion.
  ///
  /// - Parameters:
  ///   - code: The status code of the close frame.
  ///   - reason: The reason of the close frame.
  func close(code: WebSocketCloseCode, reason: String?) async
}

/// A frame on the wire, either direction.
public enum WebSocketFrame: Sendable, Hashable {
  /// A UTF-8 text frame.
  case text(String)
  /// A binary frame.
  case binary(Data)
}

/// What a ``WebSocketConnection`` reports on its `events` stream.
public enum WebSocketEvent: Sendable, Hashable {
  /// A frame from the peer.
  case frame(WebSocketFrame)
  /// The final event. `code` is `nil` when the peer closed without a status (RFC 6455 1005)
  /// or the connection dropped before any close frame.
  case closed(code: WebSocketCloseCode?, reason: String?)
}

/// An RFC 6455 close status code.
///
/// A struct rather than an enum: the peer can send any code in `1000...4999`, and application
/// codes above 4000 are project-defined.
public struct WebSocketCloseCode: RawRepresentable, Sendable, Hashable {
  /// The numeric code.
  public let rawValue: Int

  /// Creates a close code from its number.
  public init(rawValue: Int) {
    self.rawValue = rawValue
  }

  /// 1000: the purpose of the connection is fulfilled.
  public static let normalClosure = WebSocketCloseCode(rawValue: 1000)
  /// 1001: the endpoint is going away, such as a server restart.
  public static let goingAway = WebSocketCloseCode(rawValue: 1001)
  /// 1002: the peer broke the protocol.
  public static let protocolError = WebSocketCloseCode(rawValue: 1002)
  /// 1006: the connection dropped without a close frame. Never sent on the wire.
  public static let abnormalClosure = WebSocketCloseCode(rawValue: 1006)
}
