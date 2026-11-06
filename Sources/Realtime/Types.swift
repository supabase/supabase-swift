//
//  Types.swift
//
//
//  Created by Guilherme Souza on 13/05/24.
//

import Foundation
import HTTPTypes
public import Helpers
public import Logging

#if canImport(FoundationNetworking)
  public import FoundationNetworking
#endif

/// The subscription state of a ``RealtimeChannel``, with the reason when there is one.
///
/// The set of cases is fixed until the next major version, so a `switch` needs no `default`.
/// The type is not `Equatable`: use ``isSubscribed`` and ``error``, or match a case.
///
/// ```swift
/// for await status in await channel.statusChanges() {
///   switch status {
///   case .resubscribing(_, let retryIn, let lastError):
///     print("Joining again in \(retryIn) after: \(lastError.message)")
///   case .failed(let error):
///     print("Gave up: \(error.message)")
///   default:
///     break
///   }
/// }
/// ```
///
/// ## Topics
/// ### States
/// - ``unsubscribed``
/// - ``subscribing(attempt:)``
/// - ``subscribed``
/// - ``resubscribing(attempt:retryIn:lastError:)``
/// - ``unsubscribing``
/// - ``failed(_:)``
/// ### Predicates
/// - ``isSubscribed``
/// - ``error``
public enum RealtimeChannelStatus: Sendable {
  /// The channel has not joined the topic, or has left it.
  case unsubscribed

  /// The channel sent `phx_join` and waits for the server to confirm it. Attempt 1 is the
  /// first join of a ``RealtimeChannel/subscribe()`` call; later attempts are rejoins.
  case subscribing(attempt: Int)

  /// The server confirmed the join. The channel receives events.
  case subscribed

  /// Join attempt `attempt` failed with `lastError`. The channel joins again after `retryIn`.
  case resubscribing(attempt: Int, retryIn: Duration, lastError: RealtimeError)

  /// The channel sent `phx_leave` and waits for the server to close it.
  case unsubscribing

  /// ``RealtimeChannel/subscribe()`` stopped because a retry cannot help. Call it again to
  /// start over.
  case failed(RealtimeError)

  /// Whether the channel is ``subscribed``.
  public var isSubscribed: Bool {
    if case .subscribed = self { true } else { false }
  }

  /// The error behind ``resubscribing(attempt:retryIn:lastError:)`` or ``failed(_:)``, or `nil`.
  public var error: RealtimeError? {
    switch self {
    case .resubscribing(_, _, let error), .failed(let error): error
    case .unsubscribed, .subscribing, .subscribed, .unsubscribing: nil
    }
  }
}

extension RealtimeChannelStatus {
  /// Whether `other` is the same case with the same values, so a repeat is not emitted.
  func isSame(as other: RealtimeChannelStatus) -> Bool {
    switch (self, other) {
    case (.unsubscribed, .unsubscribed), (.subscribed, .subscribed),
      (.unsubscribing, .unsubscribing):
      true
    case (.subscribing(let a), .subscribing(let b)):
      a == b
    case (.resubscribing(let a, let da, let ea), .resubscribing(let b, let db, let eb)):
      a == b && da == db && ea.isSameFailure(as: eb)
    case (.failed(let a), .failed(let b)):
      a.isSameFailure(as: b)
    default:
      false
    }
  }
}

/// The connection state of a ``RealtimeClient``, with the reason when there is one.
///
/// The set of cases is fixed until the next major version, so a `switch` needs no `default`.
/// The type is not `Equatable`: use ``isConnected`` and ``error``, or match a case.
///
/// ```swift
/// for await status in await client.statusChanges() {
///   if case .reconnecting(let attempt, let retryIn, _) = status {
///     print("Attempt \(attempt + 1) in \(retryIn)")
///   }
/// }
/// ```
///
/// ## Topics
/// ### States
/// - ``disconnected(_:)``
/// - ``connecting(attempt:)``
/// - ``connected``
/// - ``reconnecting(attempt:retryIn:lastError:)``
/// ### Predicates
/// - ``isConnected``
/// - ``error``
public enum RealtimeClientStatus: Sendable {
  /// The WebSocket is closed. The error is set when a failure, not the caller, closed it.
  case disconnected(RealtimeError?)

  /// The client is opening the WebSocket. Attempt 1 is the caller's
  /// ``RealtimeClient/connect()``; later attempts reconnect after a drop.
  case connecting(attempt: Int)

  /// The WebSocket is open.
  case connected

  /// Connection attempt `attempt` failed or the socket dropped with `lastError`. The client
  /// opens the WebSocket again after `retryIn`.
  case reconnecting(attempt: Int, retryIn: Duration, lastError: RealtimeError)

  /// Whether the client is ``connected``.
  public var isConnected: Bool {
    if case .connected = self { true } else { false }
  }

  /// The error behind ``disconnected(_:)`` or ``reconnecting(attempt:retryIn:lastError:)``,
  /// or `nil`.
  public var error: RealtimeError? {
    switch self {
    case .disconnected(let error): error
    case .reconnecting(_, _, let error): error
    case .connecting, .connected: nil
    }
  }
}

extension RealtimeClientStatus {
  /// Whether `other` is the same case with the same values.
  func isSame(as other: RealtimeClientStatus) -> Bool {
    switch (self, other) {
    case (.connected, .connected):
      true
    case (.disconnected(let a), .disconnected(let b)):
      a?.isSameFailure(as: b) ?? (b == nil)
    case (.connecting(let a), .connecting(let b)):
      a == b
    case (.reconnecting(let a, let da, let ea), .reconnecting(let b, let db, let eb)):
      a == b && da == db && ea.isSameFailure(as: eb)
    default:
      false
    }
  }
}

/// A server event about a ``RealtimeChannel``, emitted by ``RealtimeChannel/events()``.
///
/// ## Topics
/// ### Events
/// - ``resubscribed``
/// - ``postgresChangesReady``
/// - ``postgresChangesFailed(_:)``
/// - ``replicationReady``
/// - ``replicationFailed(_:)``
public enum RealtimeChannelEvent: Sendable, Equatable {
  /// The channel joined again after it was subscribed, for example after a reconnect. Events
  /// sent while it was away were missed; reload any state built from them.
  case resubscribed

  /// The server set up the channel's Postgres changes subscriptions ("Subscribed to
  /// PostgreSQL"). Changes from now on are delivered.
  case postgresChangesReady

  /// The server could not set up the channel's Postgres changes subscriptions. The channel
  /// stays subscribed, so broadcast and presence keep working. The value is the server's
  /// message.
  case postgresChangesFailed(String)

  /// The Postgres replication connection behind the channel is ready ("Replication connection
  /// established"). The server sends it only when you opt in with
  /// ``RealtimeChannelConfiguration/Broadcast-swift.struct/waitForReplication``.
  case replicationReady

  /// The Postgres replication connection did not become ready in time. The server sends it only
  /// when you opt in with ``RealtimeChannelConfiguration/Broadcast-swift.struct/waitForReplication``. The value is the server's
  /// message.
  case replicationFailed(String)
}

/// One step of the heartbeat cycle, emitted by ``RealtimeClient/heartbeats()``.
///
/// The client sends a heartbeat every ``RealtimeClient/Configuration/defaultHeartbeatInterval``. When
/// the next one is due and the server has not acknowledged the previous one, the client
/// reports ``timedOut`` and reconnects.
///
/// ## Topics
/// ### Events
/// - ``sent``
/// - ``acknowledged(latency:)``
/// - ``timedOut``
public enum HeartbeatEvent: Sendable, Equatable {
  /// The client sent a heartbeat.
  case sent

  /// The server acknowledged the heartbeat `latency` after it was sent.
  case acknowledged(latency: Duration)

  /// The server did not acknowledge the previous heartbeat in time. The client drops the
  /// socket and reconnects.
  case timedOut
}

extension HTTPField.Name {
  static let apiKey = Self("apiKey")!
}

/// How much the Realtime server logs for one connection.
///
/// Set it on ``RealtimeClient/Configuration/serverLogLevel``. The client sends it as the `log_level`
/// query item of the WebSocket URL. It does not change what the client's own `logger` prints.
///
/// The type is open: a level this SDK has no member for still works.
///
/// ```swift
/// var configuration = RealtimeClient.Configuration(url: realtimeURL)
/// configuration.serverLogLevel = .warning
/// ```
///
/// ## Topics
/// ### Levels
/// - ``info``
/// - ``warning``
/// - ``error``
public struct RealtimeServerLogLevel: RawRepresentable, Hashable, Sendable,
  ExpressibleByStringLiteral
{
  /// The value sent as the `log_level` query item.
  public let rawValue: String

  /// Creates a level from its raw value.
  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// Creates a level from a string literal.
  public init(stringLiteral value: String) {
    self.init(rawValue: value)
  }

  /// Informational messages and above.
  public static let info: RealtimeServerLogLevel = "info"

  /// Warnings and errors. Sent as `warn`.
  public static let warning: RealtimeServerLogLevel = "warn"

  /// Errors only.
  public static let error: RealtimeServerLogLevel = "error"
}
