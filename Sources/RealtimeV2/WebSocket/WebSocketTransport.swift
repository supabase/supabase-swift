//
//  WebSocketTransport.swift
//  Realtime
//
//  Created by Guilherme Souza on 06/10/26.
//

import ConcurrencyExtras
public import Foundation
public import HTTPTypes

/// Opens WebSocket connections for a ``RealtimeClientV2``.
///
/// The client owns one connection at a time and reads it through ``WebSocketConnection``. The
/// default is the SDK's `URLSession` stack. Set ``RealtimeClientOptions/webSocketTransport`` to
/// use another WebSocket stack.
///
/// When `connect` throws, the client treats the attempt as failed and follows its reconnect
/// rules, whatever the error is.
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

  /// Sends one frame and returns once the transport has accepted it. The client sends frames
  /// one at a time, in order. When this method throws, the client closes the connection.
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
public struct WebSocketCloseCode: RawRepresentable, Hashable, Sendable, ExpressibleByIntegerLiteral
{
  /// The numeric status code.
  public let rawValue: Int

  /// Creates a close code from its numeric value.
  public init(rawValue: Int) {
    self.rawValue = rawValue
  }

  /// Creates a close code from an integer literal.
  public init(integerLiteral value: Int) {
    self.init(rawValue: value)
  }

  /// 1000: the connection did its job.
  public static let normalClosure: WebSocketCloseCode = 1000
  /// 1001: an endpoint is going away, such as a server shutting down.
  public static let goingAway: WebSocketCloseCode = 1001
  /// 1002: an endpoint got a frame that breaks the protocol.
  public static let protocolError: WebSocketCloseCode = 1002
  /// 1006: the connection dropped without a close frame. Never sent on the wire.
  public static let abnormalClosure: WebSocketCloseCode = 1006
}

/// Lets the client's engine, which speaks ``WebSocket``, drive a ``WebSocketConnection``.
final class WebSocketConnectionAdapter: WebSocket {
  struct MutableState {
    var isClosed = false
    var closeCode: Int?
    var closeReason: String?
  }

  let events: AsyncStream<LegacyWebSocketEvent>
  let `protocol` = ""

  private let connection: any WebSocketConnection
  private let eventsContinuation: AsyncStream<LegacyWebSocketEvent>.Continuation
  private let outbox: AsyncStream<WebSocketFrame>.Continuation
  private let mutableState = LockIsolated(MutableState())

  var closeCode: Int? { mutableState.value.closeCode }
  var closeReason: String? { mutableState.value.closeReason }
  var isClosed: Bool { mutableState.value.isClosed }

  init(_ connection: any WebSocketConnection) {
    self.connection = connection
    (events, eventsContinuation) = AsyncStream.makeStream()
    let (frames, outbox) = AsyncStream<WebSocketFrame>.makeStream()
    self.outbox = outbox

    // The engine sends without waiting, and the connection's `send` is `async`. One task sends
    // the frames in call order.
    Task { [weak self] in
      for await frame in frames {
        do {
          try await connection.send(frame)
        } catch {
          self?.didClose(code: 1006, reason: error.localizedDescription)
          connection.close(code: .abnormalClosure, reason: nil)
          return
        }
      }
    }

    Task { [weak self] in
      for await event in connection.events {
        guard let self else { return }
        switch event {
        case .frame(.text(let text)): self.eventsContinuation.yield(.text(text))
        case .frame(.binary(let data)): self.eventsContinuation.yield(.binary(data))
        case .closed(let code, let reason):
          self.didClose(code: code?.rawValue, reason: reason ?? "")
        }
      }
      self?.didClose(code: nil, reason: "")
    }
  }

  func send(_ text: String) {
    guard !isClosed else { return }
    outbox.yield(.text(text))
  }

  func send(_ binary: Data) {
    guard !isClosed else { return }
    outbox.yield(.binary(binary))
  }

  func close(code: Int?, reason: String?) {
    guard !isClosed else { return }
    // The engine passes no code for a plain disconnect. The public protocol needs one.
    connection.close(
      code: code.map(WebSocketCloseCode.init(rawValue:)) ?? .normalClosure, reason: reason)
    didClose(code: code, reason: reason ?? "")
  }

  /// Reports the close to the engine once, then ends the streams.
  private func didClose(code: Int?, reason: String) {
    let isFirst = mutableState.withValue { state in
      guard !state.isClosed else { return false }
      state.isClosed = true
      state.closeCode = code
      state.closeReason = reason
      return true
    }
    guard isFirst else { return }
    eventsContinuation.yield(.close(code: code, reason: reason))
    eventsContinuation.finish()
    outbox.finish()
  }
}
