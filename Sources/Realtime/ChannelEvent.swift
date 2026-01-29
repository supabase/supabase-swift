//
//  ChannelEvent.swift
//  Realtime
//
//  Created by Guilherme Souza on 26/12/23.
//

import Foundation

/// Constants representing the different events used in Realtime channel communication.
///
/// These events are used internally by the Realtime client to manage channel lifecycle,
/// presence synchronization, broadcast messages, and Postgres change notifications.
public enum ChannelEvent {
  /// Event sent when joining a channel.
  public static let join = "phx_join"

  /// Event sent when leaving a channel.
  public static let leave = "phx_leave"

  /// Event sent when a channel is closed.
  public static let close = "phx_close"

  /// Event sent when an error occurs on the channel.
  public static let error = "phx_error"

  /// Event sent as a reply to a previous message.
  public static let reply = "phx_reply"

  /// Event sent for system-level messages.
  public static let system = "system"

  /// Event sent for broadcast messages between clients.
  public static let broadcast = "broadcast"

  /// Event sent to update the access token for authentication.
  public static let accessToken = "access_token"

  /// Event sent for presence-related messages.
  public static let presence = "presence"

  /// Event sent when presence state changes (joins or leaves).
  public static let presenceDiff = "presence_diff"

  /// Event sent to synchronize the full presence state.
  public static let presenceState = "presence_state"

  /// Event sent for Postgres database change notifications.
  public static let postgresChanges = "postgres_changes"

  /// Event sent periodically to maintain the connection.
  public static let heartbeat = "heartbeat"

  static func isLifecyleEvent(_ event: String) -> Bool {
    switch event {
    case join, leave, reply, error, close: true
    default: false
    }
  }
}
