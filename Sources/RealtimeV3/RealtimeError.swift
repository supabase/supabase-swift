//
//  RealtimeError.swift
//  RealtimeV3
//
//  Created by Guilherme Souza on 27/06/26.
//

import Foundation

public enum RealtimeError: Error, Sendable, Equatable {
  public static func == (lhs: RealtimeError, rhs: RealtimeError) -> Bool {
    switch (lhs, rhs) {
    case (.disconnected, .disconnected): true
    case (.channelJoinTimeout, .channelJoinTimeout): true
    case (.broadcastAckTimeout, .broadcastAckTimeout): true
    case (.notSubscribed, .notSubscribed): true
    case (.cannotRegisterAfterJoin, .cannotRegisterAfterJoin): true
    case (.unknownToken, .unknownToken): true
    case (.cancelled, .cancelled): true
    case (.channelJoinRejected(let a), .channelJoinRejected(let b)): a == b
    case (.channelClosed(let a), .channelClosed(let b)): a == b
    case (.broadcastFailed(let a), .broadcastFailed(let b)): a == b
    case (.postgresSubscriptionFailed(let a), .postgresSubscriptionFailed(let b)): a == b
    case (.authenticationFailed(let ar, _), .authenticationFailed(let br, _)): ar == br
    case (.rateLimited(let a), .rateLimited(let b)): a == b
    case (.serverError(let ac, let am), .serverError(let bc, let bm)): ac == bc && am == bm
    case (.decoding(let at, _), .decoding(let bt, _)): at == bt
    case (.transportFailure, .transportFailure): true
    case (.reconnectionGaveUp, .reconnectionGaveUp): true
    case (.encoding, .encoding): true
    default: false
    }
  }

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
