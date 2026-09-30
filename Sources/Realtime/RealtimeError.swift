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

    /// The WebSocket could not be opened, or closed before it was ready.
    public static let connection: Kind = "connection"
    /// A subscribe, push, heartbeat or REST broadcast did not complete within the configured
    /// timeout.
    public static let timeout: Kind = "timeout"
    /// `httpSend` needs an access token and none was available.
    public static let accessTokenMissing: Kind = "accessTokenMissing"
    /// Every subscribe attempt failed. See `RealtimeClientOptions.maxRetryAttempts`.
    public static let maxRetryAttemptsReached: Kind = "maxRetryAttemptsReached"
    /// The server closed the channel while a subscribe was in flight.
    public static let channelClosedByServer: Kind = "channelClosedByServer"
    /// The REST broadcast endpoint answered with a non-202 status. ``RealtimeError/response``
    /// has the body.
    public static let server: Kind = "server"
    /// A REST broadcast request never completed. ``RealtimeError/underlyingError`` is usually a
    /// `URLError`.
    public static let transport: Kind = "transport"
    /// A frame from the server could not be decoded, or a message had an unexpected shape.
    public static let decoding: Kind = "decoding"
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

  static func connection(_ message: String, underlyingError: (any Error)? = nil) -> RealtimeError {
    RealtimeError(kind: .connection, message: message, underlyingError: underlyingError)
  }
}
