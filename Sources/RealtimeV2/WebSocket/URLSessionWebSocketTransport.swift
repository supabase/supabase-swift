//
//  URLSessionWebSocketTransport.swift
//  Realtime
//
//  Created by Guilherme Souza on 06/10/26.
//

import ConcurrencyExtras
public import Foundation
public import HTTPTypes

#if canImport(FoundationNetworking)
  public import FoundationNetworking
#endif

/// A ``WebSocketTransport`` built on `URLSessionWebSocketTask`.
///
/// Every connection gets its own `URLSession` copied from `configuration`, so process-wide
/// `URLSession` state never reaches the socket and the session can be invalidated on close.
/// `delegate` is consulted for authentication challenges only, which is how an app pins
/// certificates:
///
/// ```swift
/// var options = RealtimeClientOptions()
/// options.webSocketTransport = URLSessionWebSocketTransport(
///   configuration: pinnedSession.configuration,
///   delegate: pinnedSession.delegate
/// )
/// ```
///
/// On watchOS the system blocks `URLSessionWebSocketTask` for most apps, and the connection
/// waits forever (Apple's TN3135). The transport therefore refuses to connect there unless the
/// app opts in with `allowsWatchOSConnections`.
///
/// > Note: When ``RealtimeClientOptions/webSocketTransport`` is `nil`, the client uses the same
/// > `URLSession` stack directly, and does not apply the watchOS check.
public struct URLSessionWebSocketTransport: WebSocketTransport, @unchecked Sendable {
  let configuration: URLSessionConfiguration
  let delegate: (any URLSessionDelegate)?
  let allowsWatchOSConnections: Bool

  /// Creates a transport.
  ///
  /// - Parameters:
  ///   - configuration: The configuration each connection's `URLSession` uses. The transport
  ///     keeps a copy, so later changes to `configuration` do not reach it.
  ///   - delegate: Answers authentication challenges. Other delegate methods are not called.
  ///   - allowsWatchOSConnections: Set to `true` only when the watchOS app runs in a context
  ///     where the system allows WebSockets, such as audio streaming. On watchOS, `connect` throws
  ///     a ``RealtimeError`` of kind ``RealtimeError/Kind-swift.struct/invalidRequest`` when this
  ///     is `false`. It has no effect on other platforms. Defaults to `false`.
  public init(
    configuration: URLSessionConfiguration = .default,
    delegate: (any URLSessionDelegate)? = nil,
    allowsWatchOSConnections: Bool = false
  ) {
    self.configuration = configuration.copy() as! URLSessionConfiguration
    self.delegate = delegate
    self.allowsWatchOSConnections = allowsWatchOSConnections
  }

  /// Performs the HTTP upgrade and returns the open connection.
  ///
  /// The connection sends the close codes 1000 and 3000...4999. For any other code, such as
  /// ``WebSocketCloseCode/goingAway``, it closes without a status. It cuts a close reason that
  /// is over 123 bytes.
  ///
  /// - Throws: ``RealtimeError`` of kind ``RealtimeError/Kind-swift.struct/invalidRequest`` when
  ///   `url` is not a `ws:` or `wss:` URL, or on watchOS without the opt-in. Any other failure
  ///   is the error of the `URLSession` stack.
  public func connect(to url: URL, headerFields: HTTPFields) async throws
    -> any WebSocketConnection
  {
    guard url.scheme == "ws" || url.scheme == "wss" else {
      throw RealtimeError.invalidRequest("Only ws: and wss: URLs are supported, got \(url).")
    }
    #if os(watchOS)
      guard allowsWatchOSConnections else {
        throw RealtimeError.invalidRequest(
          "watchOS blocks WebSockets for most apps. Pass allowsWatchOSConnections: true to connect."
        )
      }
    #endif
    let socket = try await URLSessionWebSocket.connect(
      to: url,
      headers: headerFields.dictionary,
      configuration: configuration,
      delegate: delegate
    )
    return URLSessionWebSocketConnection(socket)
  }
}

/// Shows the SDK's own socket as a ``WebSocketConnection``.
final class URLSessionWebSocketConnection: WebSocketConnection {
  let events: AsyncStream<WebSocketEvent>
  private let socket: any WebSocket

  init(_ socket: any WebSocket) {
    self.socket = socket
    events = AsyncStream(
      socket.events.map { event -> WebSocketEvent in
        switch event {
        case .text(let text): .frame(.text(text))
        case .binary(let data): .frame(.binary(data))
        case .close(let code, let reason):
          .closed(code: code.map(WebSocketCloseCode.init(rawValue:)), reason: reason)
        }
      })
  }

  func send(_ frame: WebSocketFrame) async throws {
    switch frame {
    case .text(let text): socket.send(text)
    case .binary(let data): socket.send(data)
    }
  }

  func close(code: WebSocketCloseCode, reason: String?) {
    // The socket traps on a code or a reason it cannot send.
    let isSendable = code == .normalClosure || (3000...4999).contains(code.rawValue)
    socket.close(code: isSendable ? code.rawValue : nil, reason: reason.map(Self.cut))
  }

  /// The longest prefix of `reason` that fits the 123 bytes a close frame allows.
  private static func cut(_ reason: String) -> String {
    var reason = reason
    while reason.utf8.count > 123 {
      reason.removeLast()
    }
    return reason
  }
}
