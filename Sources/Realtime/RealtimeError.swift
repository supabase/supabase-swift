//
//  RealtimeError.swift
//
//
//  Created by Guilherme Souza on 30/10/23.
//

import Foundation
public import Helpers

/// An error thrown by the Realtime client and channels.
///
/// Check ``kind`` to learn what failed. ``response`` is set only for
/// ``Kind-swift.struct/server``, which comes from the REST broadcast endpoint used by
/// `httpSend`. WebSocket failures carry the transport error in ``underlyingError`` when there
/// is one.
///
/// ```swift
/// do {
///   try await channel.subscribeWithError()
/// } catch let error as RealtimeError where error.kind == .maxRetryAttemptsReached {
///   scheduleRetry()
/// }
/// ```
public struct RealtimeError: SupabaseError {
  /// What failed. Compare against the static members and keep a fallback branch.
  public struct Kind: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
      self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
      self.init(rawValue: value)
    }

    /// A subscribe, push, heartbeat or REST broadcast did not complete within the configured
    /// timeout. Retry, or raise `RealtimeClientOptions.timeoutInterval` if it happens often.
    public static let timeout: Kind = "timeout"
    /// `httpSend` needs an access token and none was available. Sign in, or pass an
    /// `accessToken` closure, before sending. No request was sent.
    public static let accessTokenMissing: Kind = "accessTokenMissing"
    /// Every subscribe attempt failed and the SDK gave up. Schedule a retry later, or raise
    /// `RealtimeClientOptions.maxRetryAttempts`.
    public static let maxRetryAttemptsReached: Kind = "maxRetryAttemptsReached"
    /// The server closed the channel while a subscribe was in flight. Retrying as-is is unlikely
    /// to help; check the topic and the user's access to it.
    public static let channelClosedByServer: Kind = "channelClosedByServer"
    /// The REST broadcast endpoint answered with a non-202 status. Read
    /// ``RealtimeError/response`` for the status and body.
    public static let server: Kind = "server"
    /// The network path failed: a REST broadcast never completed, or the WebSocket could not be
    /// opened or closed before it was ready. Retry or check connectivity.
    /// ``RealtimeError/underlyingError`` is the `URLError` when there was one.
    public static let transport: Kind = "transport"
    /// A frame from the server could not be decoded, or a message had an unexpected shape.
    /// Nothing to retry; report it.
    public static let decoding: Kind = "decoding"

    /// A frame could not be encoded for sending. Never thrown to callers; it only appears in logs.
    static let encoding: Kind = "encoding"
  }

  public var kind: Kind
  public var message: String
  public var response: HTTPErrorResponse?
  public var underlyingError: (any Error)?

  public init(
    kind: Kind,
    message: String,
    response: HTTPErrorResponse? = nil,
    underlyingError: (any Error)? = nil
  ) {
    self.kind = kind
    self.message = message
    self.response = response
    self.underlyingError = underlyingError
  }

  public var description: String {
    formattedDescription(kind: kind.rawValue)
  }
}

extension RealtimeError {
  /// Every subscribe attempt failed.
  public static let maxRetryAttemptsReached = RealtimeError(
    kind: .maxRetryAttemptsReached, message: "Maximum retry attempts reached.")

  /// The server closed the channel while a subscribe was in flight.
  public static let channelClosedByServer = RealtimeError(
    kind: .channelClosedByServer, message: "Channel was closed by the server while subscribing.")

  static let accessTokenMissing = RealtimeError(
    kind: .accessTokenMissing, message: "Access token is required for httpSend()")

  static let heartbeatTimeout = RealtimeError(kind: .timeout, message: "heartbeat timeout")

  static func decoding(_ message: String) -> RealtimeError {
    RealtimeError(kind: .decoding, message: message)
  }

  static func encoding(_ message: String) -> RealtimeError {
    RealtimeError(kind: .encoding, message: message)
  }

  static func transport(_ message: String, underlyingError: (any Error)? = nil) -> RealtimeError {
    RealtimeError(kind: .transport, message: message, underlyingError: underlyingError)
  }
}
