//
//  CoreTypes.swift
//  Realtime
//

import Foundation
import Helpers

/// A message reference. Refs go on the wire as strings: `"1"`, `"2"`, …
typealias Ref = String

/// One caller that waits in the shell until the core resolves it with ``RealtimeCore/Effect/resume(_:_:)``.
struct WaiterID: Hashable, Sendable {
  let rawValue: UInt64
}

/// When an event happens. The core has no clock, so the shell passes the time in.
struct CoreTime: Sendable {
  /// The time since the client was created.
  var elapsed: Duration
  /// The wall-clock time, for token expiry.
  var date: Date
}

/// How a wait ends.
enum WaiterOutcome: Equatable, Sendable {
  case success
  case failure(RealtimeError)
  /// The wait ended with no outcome: a disconnect interrupted it, or its caller was cancelled.
  case cancelled

  static func == (lhs: WaiterOutcome, rhs: WaiterOutcome) -> Bool {
    switch (lhs, rhs) {
    case (.success, .success), (.cancelled, .cancelled):
      return true
    case (.failure(let a), .failure(let b)):
      return a.isSameFailure(as: b)
    default:
      return false
    }
  }
}

/// A timer the core starts with ``RealtimeCore/Effect/schedule(_:after:)``. Scheduling an id
/// again replaces its pending timer.
enum TimerID: Hashable, Sendable {
  /// The next heartbeat is due, and the previous one must have been acknowledged.
  case heartbeat
  case tokenRefresh
  case joinTimeout(topic: String, ref: Ref)
  case rejoin(topic: String)
  case postgresTimeout(topic: String, ref: Ref)
  case leaveTimeout(topic: String, ref: Ref)
  case pushTimeout(topic: String, ref: Ref)
}

/// One element for the streams of a channel's sinks.
enum Delivery: Sendable, Equatable {
  case broadcast(BroadcastMessage)
  case postgres(PostgresDelivery)
  case presence(PresenceChange, PresenceState)
  case event(RealtimeChannelEvent)
}

/// What a join payload depends on besides the configuration, read from the channel's sinks when
/// the command is made.
struct JoinSnapshot: Sendable, Equatable {
  /// The Postgres bindings of the open streams, in registration order.
  var bindings: [PostgresJoinConfig]
  /// Whether a presence stream is open.
  var presenceEnabled: Bool
}

/// The payload of a broadcast the client sends as a binary frame.
enum BroadcastPushPayload: Sendable, Hashable {
  case json(JSONObject)
  case binary(Data)
}
