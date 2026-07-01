//
//  PhoenixMessage.swift
//  RealtimeV3
//
//  Created by Guilherme Souza on 27/06/26.
//

import Foundation

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
  public let event: String

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
    event: String,
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
