//
//  WebSocketTransport.swift
//  Realtime
//
//  Created by Guilherme Souza on 06/10/26.
//

package import Foundation
package import HTTPTypes

/// Opens WebSocket connections for the Realtime engine.
///
/// The engine owns one connection at a time and reads it through ``WebSocketConnection``. The
/// default is ``URLSessionWebSocketTransport``; tests inject a stub.
package protocol WebSocketTransport: Sendable {
  /// Performs the HTTP upgrade and returns the open connection.
  ///
  /// Throws `RealtimeError` with kind `.transport`. The error's `isRetryable` tells the engine
  /// whether to back off and try again (network failure, 429, 5xx) or to stop (401, 403, 404).
  /// Rethrows `CancellationError` when the calling task is cancelled mid-handshake.
  func connect(to url: URL, headerFields: HTTPFields) async throws -> any WebSocketConnection
}

/// One open WebSocket connection.
package protocol WebSocketConnection: Sendable {
  /// Every frame the peer sends, then exactly one ``WebSocketEvent/closed(code:reason:)``,
  /// after which the stream finishes. A close is an event, never a thrown error.
  var events: AsyncStream<WebSocketEvent> { get }

  /// Sends one frame and returns once the transport has accepted it. Frames go out in call
  /// order, so the engine can rely on `phx_join` reaching the wire before anything sent after.
  func send(_ frame: WebSocketFrame) async throws

  /// Starts a graceful close. The `.closed` event on ``events`` reports completion.
  func close(code: WebSocketCloseCode, reason: String?) async
}

/// A frame on the wire, either direction.
package enum WebSocketFrame: Sendable, Hashable {
  case text(String)
  case binary(Data)
}

/// What a ``WebSocketConnection`` reports on its `events` stream.
package enum WebSocketEvent: Sendable, Hashable {
  case frame(WebSocketFrame)
  /// The final event. `code` is `nil` when the peer closed without a status (RFC 6455 1005)
  /// or the connection dropped before any close frame.
  case closed(code: WebSocketCloseCode?, reason: String?)
}

/// An RFC 6455 close status code.
///
/// A struct rather than an enum: the peer can send any code in `1000...4999`, and application
/// codes above 4000 are project-defined.
package struct WebSocketCloseCode: RawRepresentable, Sendable, Hashable {
  package let rawValue: Int

  package init(rawValue: Int) {
    self.rawValue = rawValue
  }

  package static let normalClosure = WebSocketCloseCode(rawValue: 1000)
  package static let goingAway = WebSocketCloseCode(rawValue: 1001)
  package static let protocolError = WebSocketCloseCode(rawValue: 1002)
  package static let abnormalClosure = WebSocketCloseCode(rawValue: 1006)
}
