//
//  ChannelEvent.swift
//
//
//  Created by Guilherme Souza on 15/04/24.
//

import Foundation

/// Represents the different events that can be sent through
/// a channel regarding a Channel's lifecycle.
enum ChannelEvent {
  static let join = "phx_join"
  static let leave = "phx_leave"
  static let close = "phx_close"
  static let error = "phx_error"
  static let reply = "phx_reply"
  static let system = "system"
  static let broadcast = "broadcast"
  static let accessToken = "access_token"
  static let presence = "presence"
  static let presenceDiff = "presence_diff"
  static let presenceState = "presence_state"
  static let postgresChanges = "postgres_changes"

  static let heartbeat = "heartbeat"

  static func isLifecyleEvent(_ event: String) -> Bool {
    switch event {
    case join, leave, reply, error, close: true
    default: false
    }
  }
}
