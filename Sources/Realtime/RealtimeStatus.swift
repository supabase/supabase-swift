//
//  RealtimeStatus.swift
//  Realtime
//
//  Created by Guilherme Souza on 08/10/26.
//

/// The state of the Realtime socket.
///
/// The set of cases is frozen; a new case only comes in a major release. The type is not
/// `Equatable`: check ``isConnected`` and ``error``, or pattern match.
public enum RealtimeConnectionStatus: Sendable {
  /// The socket is closed: never connected, disconnected or paused by the app, or stopped by a
  /// fatal failure, which the associated error carries.
  case disconnected(RealtimeError?)
  /// The socket is opening. `attempt` starts at 1.
  case connecting(attempt: Int)
  /// The socket is open.
  case connected
  /// The socket was lost and the SDK opens it again after `retryIn`.
  case reconnecting(attempt: Int, retryIn: Duration, lastError: RealtimeError)

  /// Whether the socket is open.
  public var isConnected: Bool {
    if case .connected = self { return true }
    return false
  }

  /// The error from ``disconnected(_:)`` or ``reconnecting(attempt:retryIn:lastError:)``.
  public var error: RealtimeError? {
    switch self {
    case .disconnected(let error): error
    case .reconnecting(_, _, let error): error
    case .connecting, .connected: nil
    }
  }
}

/// The state of one channel's subscription.
///
/// The set of cases is frozen; a new case only comes in a major release. The type is not
/// `Equatable`: check ``isSubscribed`` and ``error``, or pattern match.
public enum RealtimeChannelStatus: Sendable {
  /// The channel is not joined and does not want to be.
  case unsubscribed
  /// The join is in flight. `attempt` starts at 1.
  case subscribing(attempt: Int)
  /// The server acknowledged the join.
  case subscribed
  /// The channel lost its join and the SDK joins again after `retryIn`. A `retryIn` of zero
  /// means the rejoin waits for the socket or a fresh token instead of a timer.
  case resubscribing(attempt: Int, retryIn: Duration, lastError: RealtimeError)
  /// The leave is in flight.
  case unsubscribing
  /// The server refused the join for good. Fix the cause, then subscribe again.
  case failed(RealtimeError)

  /// Whether the server acknowledged the join.
  public var isSubscribed: Bool {
    if case .subscribed = self { return true }
    return false
  }

  /// The error from ``resubscribing(attempt:retryIn:lastError:)`` or ``failed(_:)``.
  public var error: RealtimeError? {
    switch self {
    case .resubscribing(_, _, let error): error
    case .failed(let error): error
    case .unsubscribed, .subscribing, .subscribed, .unsubscribing: nil
    }
  }
}

/// One step of the socket's heartbeat.
public enum HeartbeatEvent: Sendable, Equatable {
  /// A heartbeat was queued for sending.
  case sent
  /// The server replied to the last heartbeat after `latency`.
  case acknowledged(latency: Duration)
  /// The server did not reply in time; the SDK closes the socket and reconnects.
  case timedOut
}

extension ConnectionMachine.State {
  package var publicStatus: RealtimeConnectionStatus {
    switch self {
    case .disconnected(let error): .disconnected(error)
    case .connecting(let attempt): .connecting(attempt: attempt)
    case .connected: .connected
    case .reconnecting(let attempt, let retryIn, let lastError):
      .reconnecting(attempt: attempt, retryIn: retryIn, lastError: lastError)
    }
  }
}

extension ChannelMachine.State {
  package var publicStatus: RealtimeChannelStatus {
    switch self {
    case .unsubscribed: .unsubscribed
    case .subscribing(let attempt, _): .subscribing(attempt: attempt)
    case .subscribed: .subscribed
    case .resubscribing(let attempt, let retryIn, let lastError):
      .resubscribing(attempt: attempt, retryIn: retryIn, lastError: lastError)
    case .unsubscribing: .unsubscribing
    case .failed(let error): .failed(error)
    }
  }
}
