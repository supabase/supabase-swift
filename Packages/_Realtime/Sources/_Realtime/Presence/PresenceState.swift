//
//  PresenceState.swift
//  _Realtime
//
//  Created by Guilherme Souza on 24/04/25.
//

public typealias PresenceKey = String

public struct PresenceState<T: Sendable>: Sendable {
  public let active: [PresenceKey: [T]]
  public let lastDiff: PresenceDiff<T>?
}

public struct PresenceDiff<T: Sendable>: Sendable {
  public let joined: [(PresenceKey, T)]
  public let left: [(PresenceKey, T)]
}
