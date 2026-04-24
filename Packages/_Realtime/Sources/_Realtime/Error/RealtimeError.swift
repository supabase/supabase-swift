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
