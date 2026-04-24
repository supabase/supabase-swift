//
//  BroadcastMessage.swift
//  _Realtime
//
//  Created by Guilherme Souza on 24/04/25.
//

import Foundation

/// A broadcast message received from a Realtime channel.
public struct BroadcastMessage: Sendable {
  /// The event name carried by this broadcast.
  public let event: String
  /// The message payload as a `JSONValue`.
  public let payload: JSONValue
  /// The local time at which this message was received.
  public let receivedAt: Date

  public init(event: String, payload: JSONValue, receivedAt: Date = Date()) {
    self.event = event
    self.payload = payload
    self.receivedAt = receivedAt
  }
}
