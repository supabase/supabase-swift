//
//  PhoenixMessage.swift
//  RealtimeV3
//
//  Created by Guilherme Souza on 27/06/26.
//

import Foundation

// MARK: - PhoenixEvent

/// A Phoenix event name. An open `RawRepresentable` wrapper so server-sent
/// events unknown to the client still round-trip. Known events are provided
/// as static constants.
public struct PhoenixEvent: RawRepresentable, Sendable, Hashable, ExpressibleByStringLiteral {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }
  public init(stringLiteral value: String) { self.rawValue = value }

  public static let broadcast = PhoenixEvent(rawValue: "broadcast")
  public static let postgresChanges = PhoenixEvent(rawValue: "postgres_changes")
  public static let presenceState = PhoenixEvent(rawValue: "presence_state")
  public static let presenceDiff = PhoenixEvent(rawValue: "presence_diff")
  public static let system = PhoenixEvent(rawValue: "system")
  public static let reply = PhoenixEvent(rawValue: "phx_reply")
  public static let close = PhoenixEvent(rawValue: "phx_close")
  public static let error = PhoenixEvent(rawValue: "phx_error")
  public static let join = PhoenixEvent(rawValue: "phx_join")
  public static let leave = PhoenixEvent(rawValue: "phx_leave")
  public static let heartbeat = PhoenixEvent(rawValue: "heartbeat")
  public static let accessToken = PhoenixEvent(rawValue: "access_token")
}

// MARK: - PhoenixMessage

/// A Phoenix protocol message received from the WebSocket connection.
public struct PhoenixMessage: Sendable {
  /// Phoenix join reference correlating this frame to its `phx_join`. Always
  /// `nil` when the channel is configured for protocol v1 (4-tuple frames
  /// have no joinRef field). Under v2: `nil` for frames that predate the
  /// current join (rare).
  public let joinRef: String?

  /// Phoenix message reference for request/reply correlation. Set on
  /// pushes the SDK sent and on the matching `phx_reply`. `nil` for
  /// server-pushed events (`broadcast`, `postgres_changes`, etc.).
  public let ref: String?

  /// Channel topic this frame belongs to. Always matches this channel's topic
  /// for channel iterators; included on the struct so consumers that hand
  /// `PhoenixMessage` values across boundaries (logging, debugging,
  /// multi-topic aggregation) keep the routing key.
  public let topic: String

  /// Server-side event name. Includes user-level events (`"broadcast"`,
  /// `"postgres_changes"`, `"presence_diff"`, `"presence_state"`, `"system"`)
  /// and Phoenix internals (`"phx_reply"`, `"phx_close"`, `"phx_error"`).
  public let event: PhoenixEvent

  /// Raw payload as received. JSON for text frames, `Data` for binary
  /// (Phoenix v2 broadcast).
  public let payload: PhoenixPayload

  /// Local receipt timestamp.
  public let receivedAt: Date

  /// Creates a new Phoenix message.
  public init(
    joinRef: String?,
    ref: String?,
    topic: String,
    event: PhoenixEvent,
    payload: PhoenixPayload,
    receivedAt: Date
  ) {
    self.joinRef = joinRef
    self.ref = ref
    self.topic = topic
    self.event = event
    self.payload = payload
    self.receivedAt = receivedAt
  }
}

/// The payload of a Phoenix message.
public enum PhoenixPayload: Sendable {
  /// JSON payload from a text frame.
  case json(JSONValue)
  /// Binary payload from a binary frame.
  case binary(Data)
}
