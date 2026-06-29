//
//  ConnectionStatus.swift
//  RealtimeV3
//
//  Created by Guilherme Souza on 29/06/26.
//

import Foundation

/// Represents the current connection state and associated metadata.
public struct ConnectionStatus: Sendable {
  /// The discrete connection states.
  public enum State: Sendable {
    case idle
    case connecting(attempt: Int)
    case connected
    case reconnecting(attempt: Int, lastError: (any Error & Sendable)?)
    case closed(CloseReason)
  }

  /// The current connection state.
  public let state: State

  /// When the current `state` was entered. Reset on every state transition.
  public let since: Date

  /// Last successful heartbeat round-trip time, if any. `nil` before the
  /// first heartbeat reply or after the connection drops.
  public let latency: Duration?

  public init(state: State, since: Date, latency: Duration?) {
    self.state = state
    self.since = since
    self.latency = latency
  }
}
