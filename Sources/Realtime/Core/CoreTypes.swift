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

/// The identity of one channel record in the core. The shell issues it when it creates a channel
/// handle, and every command and effect for the channel carries it.
struct ChannelID: Hashable, Comparable, Sendable, CustomStringConvertible {
  let rawValue: UInt64

  var description: String { "channel#\(rawValue)" }

  static func < (lhs: ChannelID, rhs: ChannelID) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
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
  /// The backoff wait before the next reconnect attempt is over.
  case reconnect
  /// The wait after the last channel was removed is over: disconnect.
  case idleDisconnect
  case joinTimeout(channel: ChannelID, ref: Ref)
  case rejoin(channel: ChannelID)
  case postgresTimeout(channel: ChannelID, ref: Ref)
  case leaveTimeout(channel: ChannelID, ref: Ref)
  case pushTimeout(channel: ChannelID, ref: Ref)
}

/// One element for the streams of a channel.
enum Delivery: Sendable, Equatable {
  case broadcast(BroadcastMessage)
  case postgres(PostgresDelivery)
  case presence(PresenceChange, PresenceState)
  case event(RealtimeChannelEvent)
}

/// What a join payload depends on besides the configuration, read from the channel's state when
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

/// The fields of a Postgres changes binding the server matches on. `PostgresJoinConfig`'s `==`
/// treats `.all` as matching any event, which would hide a new binding.
struct BindingKey: Hashable {
  let event: PostgresChangeEvent?
  let schema: String
  let table: String?
  let filter: String?
  let select: [String]?

  init(_ binding: PostgresJoinConfig) {
    event = binding.event
    schema = binding.schema
    table = binding.table
    filter = binding.filter
    select = binding.select
  }
}
