import ConcurrencyExtras
import Foundation
import Logging

struct SessionManager: Sendable {
  var session: @Sendable () async throws -> Session
  /// Redeems `refreshToken`, or refreshes the held session when it is `nil`.
  var refreshSession: @Sendable (_ refreshToken: String?) async throws -> Session
  var refreshSessionIfNeeded: @Sendable () async throws -> Session?
}

extension SessionManager {
  static func live(
    policy: AuthClient.AutoRefreshPolicy,
    sessionStore: SessionStore,
    logger: Logging.Logger,
    request: @escaping @Sendable (_ refreshToken: String) async throws -> Session,
    beforeRefreshingHeldSession: @escaping @Sendable () async -> Void
  ) -> Self {
    let instance = LiveSessionManager(
      policy: policy,
      sessionStore: sessionStore,
      logger: logger,
      request: request,
      beforeRefreshingHeldSession: beforeRefreshingHeldSession
    )
    return Self(
      session: { try await instance.session() },
      refreshSession: { try await instance.refreshSession($0) },
      refreshSessionIfNeeded: { try await instance.refreshSessionIfNeeded() }
    )
  }
}

private struct LiveSessionManager: Sendable {
  let policy: AuthClient.AutoRefreshPolicy
  let sessionStore: SessionStore
  let logger: Logging.Logger
  let request: @Sendable (_ refreshToken: String) async throws -> Session
  let beforeRefreshingHeldSession: @Sendable () async -> Void

  func session() async throws -> Session {
    try await trace(using: logger) {
      if sessionStore.currentStatus == .loading {
        try await sessionStore.load()
      }

      if let session = sessionStore.validSession(minimumValidity: defaultExpiryMargin) {
        return session
      }

      guard let currentSession = sessionStore.currentSession else {
        logger.debug("session missing")
        throw AuthError.sessionMissing
      }

      guard policy != .disabled else {
        if let session = sessionStore.validSession(minimumValidity: .zero) {
          return session
        }
        logger.debug("session expired, auto refresh disabled")
        throw AuthError.refreshDisabled
      }

      logger.debug("session expired")
      return try await refreshHeldSession(readWith: currentSession.refreshToken)
    }
  }

  func refreshSession(_ refreshToken: String?) async throws -> Session {
    try await trace(using: logger) {
      if let refreshToken {
        return try await sessionStore.refresh(refreshToken, using: request)
      }
      guard let currentSession = sessionStore.currentSession else {
        throw AuthError.sessionMissing
      }
      return try await refreshHeldSession(readWith: currentSession.refreshToken)
    }
  }

  func refreshSessionIfNeeded() async throws -> Session? {
    try await trace(using: logger) {
      if sessionStore.currentStatus == .loading {
        try await sessionStore.load()
      }

      guard let currentSession = sessionStore.currentSession else { return nil }

      let halfLifetime = Duration.seconds(currentSession.expiresIn / 2)
      let minimumValidity = max(Refresher.refreshLeadTime, halfLifetime)
      if let session = sessionStore.validSession(minimumValidity: minimumValidity) {
        return session
      }
      return try await refreshHeldSession(readWith: currentSession.refreshToken)
    }
  }

  private func refreshHeldSession(readWith refreshToken: String) async throws -> Session {
    await beforeRefreshingHeldSession()
    return try await sessionStore.refreshHeldSession(readWith: refreshToken, using: request)
  }
}
