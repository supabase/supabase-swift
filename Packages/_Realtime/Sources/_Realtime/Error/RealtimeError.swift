import Foundation

public enum RealtimeError: Error, Sendable {
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
