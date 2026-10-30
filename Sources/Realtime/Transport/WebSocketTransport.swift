//
//  WebSocketTransport.swift
//  Realtime
//
//  Created by Guilherme Souza on 06/10/26.
//

public import Foundation
public import HTTPTypes

/// Opens WebSocket connections for a ``RealtimeClient``.
///
/// The client owns one connection at a time and reads it through ``WebSocketConnection``. The
/// default is ``URLSessionWebSocketTransport``. Set ``RealtimeClientOptions/webSocketTransport``
/// to use another WebSocket stack.
///
/// A transport must report failures in a way the client can act on:
/// - When the server answers the upgrade with an HTTP status, throw
///   ``RealtimeError/upgradeFailed(status:underlyingError:)``. A 401, 403 or 404 stops the
///   client; during an automatic reconnect, any other status lets it try again.
/// - For any other failure, such as a lost network, throw a ``RealtimeError`` with kind
///   ``RealtimeError/Kind/transport``. During an automatic reconnect, the client tries again.
///
/// A failure in ``RealtimeClient/connect()`` itself is never retried: `connect()` throws it to
/// the caller.
/// - When the calling task is cancelled during the handshake, throw `CancellationError`.
public protocol WebSocketTransport: Sendable {
  /// Performs the HTTP upgrade and returns the open connection.
  ///
  /// - Parameters:
  ///   - url: The `ws:` or `wss:` URL to open.
  ///   - headerFields: The headers to send with the upgrade request.
  /// - Returns: The open connection.
  func connect(to url: URL, headerFields: HTTPFields) async throws -> any WebSocketConnection
}

/// One open WebSocket connection. A class, so the client can tell two connections apart by
/// identity.
public protocol WebSocketConnection: AnyObject, Sendable {
  /// Every frame the peer sends, then exactly one ``WebSocketEvent/closed(code:reason:)``,
  /// after which the stream finishes. A close is an event, never a thrown error.
  var events: AsyncStream<WebSocketEvent> { get }

  /// Sends one frame and returns once the transport has accepted it. Frames go out in call
  /// order, so the client can rely on `phx_join` reaching the wire before anything sent after.
  func send(_ frame: WebSocketFrame) async throws

  /// Starts a graceful close and returns without waiting for it. The `.closed` event on
  /// ``events`` reports completion.
  func close(code: WebSocketCloseCode, reason: String?)
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
  /// A frame the peer sent.
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
  /// The numeric status code.
  public let rawValue: Int

  /// Creates a close code from its numeric value.
  public init(rawValue: Int) {
    self.rawValue = rawValue
  }

  /// 1000: the connection did its job.
  public static let normalClosure = WebSocketCloseCode(rawValue: 1000)
  /// 1001: an endpoint is going away, such as a server shutting down.
  public static let goingAway = WebSocketCloseCode(rawValue: 1001)
  /// 1002: an endpoint got a frame that breaks the protocol.
  public static let protocolError = WebSocketCloseCode(rawValue: 1002)
  /// 1006: the connection dropped without a close frame. Never sent on the wire.
  public static let abnormalClosure = WebSocketCloseCode(rawValue: 1006)
}
