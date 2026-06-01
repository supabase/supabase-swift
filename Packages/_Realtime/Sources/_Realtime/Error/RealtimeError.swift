import Foundation

public enum RealtimeError: Error, Sendable, Equatable {
  // Connection
  case disconnected
  case transportFailure(underlying: any Error & Sendable)
  case reconnectionGaveUp(lastError: any Error & Sendable)

  // Channel lifecycle
  case channelNotJoined
  case channelJoinTimeout
  case channelJoinRejected(reason: String)
  case channelClosed(CloseReason)

  // Auth
  case authenticationFailed(reason: String, underlying: (any Error & Sendable)?)
  case tokenExpired

  // Server
  case rateLimited(retryAfter: Duration?)
  case serverError(code: Int, message: String)

  // Broadcast
  case broadcastFailed(reason: String)
  case broadcastAckTimeout

  // Coding
  case decoding(type: String, underlying: any Error & Sendable)
  case encoding(underlying: any Error & Sendable)

  // Cancellation (Swift CancellationError folded here)
  case cancelled
}

public enum CloseReason: Sendable, Equatable {
  case userRequested
  case serverClosed(code: Int, message: String?)
  case timeout
  case unauthorized
  case policyViolation(String)
  case transportFailure
}

extension RealtimeError {
  public static func == (lhs: RealtimeError, rhs: RealtimeError) -> Bool {
    switch (lhs, rhs) {
    case (.disconnected, .disconnected): return true
    case (.transportFailure, .transportFailure): return true
    case (.reconnectionGaveUp, .reconnectionGaveUp): return true
    case (.channelNotJoined, .channelNotJoined): return true
    case (.channelJoinTimeout, .channelJoinTimeout): return true
    case (.channelJoinRejected(let l), .channelJoinRejected(let r)): return l == r
    case (.channelClosed(let l), .channelClosed(let r)): return l == r
    case (.authenticationFailed(let lr, _), .authenticationFailed(let rr, _)): return lr == rr
    case (.tokenExpired, .tokenExpired): return true
    case (.rateLimited(let l), .rateLimited(let r)): return l == r
    case (.serverError(let lc, let lm), .serverError(let rc, let rm)): return lc == rc && lm == rm
    case (.broadcastFailed(let l), .broadcastFailed(let r)): return l == r
    case (.broadcastAckTimeout, .broadcastAckTimeout): return true
    case (.decoding(let lt, _), .decoding(let rt, _)): return lt == rt
    case (.encoding, .encoding): return true
    case (.cancelled, .cancelled): return true
    default: return false
    }
  }
}

extension RealtimeError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .disconnected:
      return "Not connected to the Realtime server."
    case .transportFailure(let underlying):
      return "Transport failure: \(underlying.localizedDescription)"
    case .reconnectionGaveUp(let lastError):
      return "Reconnection exhausted: \(lastError.localizedDescription)"
    case .channelNotJoined:
      return "Channel is not joined."
    case .channelJoinTimeout:
      return "Channel join timed out."
    case .channelJoinRejected(let reason):
      return "Channel join rejected: \(reason)"
    case .channelClosed(let reason):
      return "Channel closed: \(reason)"
    case .authenticationFailed(let reason, _):
      return "Authentication failed: \(reason)"
    case .tokenExpired:
      return "Authentication token expired."
    case .rateLimited(let retryAfter):
      if let d = retryAfter {
        return "Rate limited. Retry after \(d)."
      }
      return "Rate limited."
    case .serverError(let code, let message):
      return "Server error \(code): \(message)"
    case .broadcastFailed(let reason):
      return "Broadcast failed: \(reason)"
    case .broadcastAckTimeout:
      return "Broadcast acknowledgement timed out."
    case .decoding(let type, let underlying):
      return "Failed to decode \(type): \(underlying.localizedDescription)"
    case .encoding(let underlying):
      return "Encoding error: \(underlying.localizedDescription)"
    case .cancelled:
      return "Operation was cancelled."
    }
  }
}
