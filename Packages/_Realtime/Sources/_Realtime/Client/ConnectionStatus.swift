//
//  ConnectionStatus.swift
//  _Realtime
//
//  Created by Guilherme Souza on 24/04/25.
//

import Foundation

public struct ConnectionStatus: Sendable, Equatable {
  public enum State: Sendable, Equatable {
    case idle
    case connecting(attempt: Int)
    case connected
    case reconnecting(attempt: Int)
    case closed(CloseReason)
  }

  public let state: State
  public let since: Date
  public let latency: Duration?

  public init(state: State, since: Date = Date(), latency: Duration? = nil) {
    self.state = state
    self.since = since
    self.latency = latency
  }

  public static func == (lhs: Self, rhs: Self) -> Bool { lhs.state == rhs.state }
}
