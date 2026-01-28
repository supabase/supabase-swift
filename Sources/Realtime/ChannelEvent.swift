//
//  ChannelEvent.swift
//
//
//  Created by Guilherme Souza on 26/12/23.
//

import Foundation

/// Represents the different events that can be sent through
/// a channel regarding a Channel's lifecycle.
public enum ChannelEvent {
  public static let join = "phx_join"
  public static let leave = "phx_leave"
  public static let close = "phx_close"
  public static let error = "phx_error"
  public static let reply = "phx_reply"
  public static let system = "system"
  public static let broadcast = "broadcast"
  public static let accessToken = "access_token"
  public static let presence = "presence"
  public static let presenceDiff = "presence_diff"
  public static let presenceState = "presence_state"
  public static let postgresChanges = "postgres_changes"
  public static let heartbeat = "heartbeat"

  static func isLifecyleEvent(_ event: String) -> Bool {
    switch event {
    case join, leave, reply, error, close: true
    default: false
    }
  }
}
