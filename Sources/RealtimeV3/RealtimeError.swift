//
//  RealtimeError.swift
//  RealtimeV3
//
//  Created by Guilherme Souza on 27/06/26.
//

import Foundation

public enum RealtimeError: Error, Sendable {
  case disconnected
  case transportFailure(underlying: any Error & Sendable)
  case reconnectionGaveUp(lastError: any Error & Sendable)

  case channelJoinTimeout
  case channelJoinRejected(reason: String)
  case notSubscribed
  case channelClosed(CloseReason)
  case cannotRegisterAfterJoin
  case unknownToken

  case authenticationFailed(reason: String, underlying: (any Error & Sendable)?)

  case rateLimited(retryAfter: Duration?)
  case serverError(code: Int, message: String)
  case postgresSubscriptionFailed(reason: String)

  case broadcastFailed(reason: String)
  case broadcastAckTimeout

  case decoding(type: String, underlying: any Error & Sendable)
  case encoding(underlying: any Error & Sendable)

  case cancelled
}

extension RealtimeError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .disconnected:
      "The realtime connection is disconnected"
    case .transportFailure:
      "A transport failure occurred"
    case .reconnectionGaveUp:
      "Reconnection attempts have been exhausted"
    case .channelJoinTimeout:
      "The channel join request timed out"
    case .channelJoinRejected(let reason):
      "Channel join was rejected: \(reason)"
    case .notSubscribed:
      "The channel is not subscribed"
    case .channelClosed:
      "The channel has been closed"
    case .cannotRegisterAfterJoin:
      "Cannot register postgres changes after the channel has joined"
    case .unknownToken:
      "Unknown token"
    case .authenticationFailed(let reason, _):
      "Authentication failed: \(reason)"
    case .rateLimited:
      "Rate limited"
    case .serverError(let code, let message):
      "Server error (\(code)): \(message)"
    case .postgresSubscriptionFailed(let reason):
      "Postgres subscription failed: \(reason)"
    case .broadcastFailed(let reason):
      "Broadcast failed: \(reason)"
    case .broadcastAckTimeout:
      "Broadcast acknowledgment timed out"
    case .decoding(let type, _):
      "Failed to decode \(type)"
    case .encoding:
      "Failed to encode value"
    case .cancelled:
      "Operation was cancelled"
    }
  }
}
