import ConcurrencyExtras
import Foundation
import Logging

struct SessionManager: Sendable {
  var session: @Sendable () async throws -> Session
  var refreshSession: @Sendable (_ refreshToken: String) async throws -> Session

  var startAutoRefresh: @Sendable () async -> Void
  var stopAutoRefresh: @Sendable () async -> Void

  var isAutoRefreshRunning: @Sendable () async -> Bool
}

extension SessionManager {
  static func live(
    configuration: AuthClient.Configuration,
    authAPI: AuthAPI,
    api: APIClient,
    sessionStore: SessionStore,
    logger: Logging.Logger
  ) -> Self {
    let instance = LiveSessionManager(
      sessionStore: sessionStore,
      logger: logger,
      clock: configuration.clock,
      request: { refreshToken in
        try await api.execute(authAPI.refreshSession(refreshToken: refreshToken))
      }
    )
    return Self(
      session: { try await instance.session() },
      refreshSession: { try await instance.refreshSession($0) },
      startAutoRefresh: { await instance.startAutoRefreshToken() },
      stopAutoRefresh: { await instance.stopAutoRefreshToken() },
      isAutoRefreshRunning: { await instance.isAutoRefreshTokenRunning() }
    )
  }
}

private struct LiveSessionManager: Sendable {
  let owner = UUID()
  let sessionStore: SessionStore
  let logger: Logging.Logger
  let clock: any Clock<Duration>
  let request: @Sendable (_ refreshToken: String) async throws -> Session

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

      logger.debug("session expired")
      return try await refreshSession(currentSession.refreshToken)
    }
  }

  func refreshSession(_ refreshToken: String) async throws -> Session {
    try await trace(using: logger) {
      try await sessionStore.refresh(refreshToken, using: request)
    }
  }

  func startAutoRefreshToken() async {
    logger.debug("start auto refresh token")
    await sessionStore.startAutoRefresh(
      for: owner, using: Refresher.Driver(clock: clock, logger: logger, request: request))
  }

  func stopAutoRefreshToken() async {
    logger.debug("stop auto refresh token")
    await sessionStore.stopAutoRefresh(for: owner)
  }

  func isAutoRefreshTokenRunning() async -> Bool {
    await sessionStore.isAutoRefreshStarted(by: owner)
  }
}
