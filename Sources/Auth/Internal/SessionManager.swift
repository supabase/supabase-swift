import ConcurrencyExtras
import Foundation
import Logging

struct SessionManager: Sendable {
  var session: @Sendable () async throws -> Session
  var refreshSession: @Sendable (_ refreshToken: String) async throws -> Session

  var startAutoRefresh: @Sendable () async -> Void
  var stopAutoRefresh: @Sendable () async -> Void

  /// Whether the auto-refresh loop is currently scheduled.
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
      configuration: configuration,
      authAPI: authAPI,
      api: api,
      sessionStore: sessionStore,
      logger: logger
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

private actor LiveSessionManager {
  private let configuration: AuthClient.Configuration
  private let authAPI: AuthAPI
  private let api: APIClient
  private let sessionStore: SessionStore
  private let logger: Logging.Logger

  private var clock: any Clock<Duration> { configuration.clock }

  private var inFlightRefreshes: [String: Task<Session, any Error>] = [:]
  private var startAutoRefreshTokenTask: Task<Void, Never>?

  init(
    configuration: AuthClient.Configuration,
    authAPI: AuthAPI,
    api: APIClient,
    sessionStore: SessionStore,
    logger: Logging.Logger
  ) {
    self.configuration = configuration
    self.authAPI = authAPI
    self.api = api
    self.sessionStore = sessionStore
    self.logger = logger
  }

  func session() async throws -> Session {
    try await trace(using: logger) {
      if sessionStore.currentStatus == .loading {
        try await sessionStore.load()
      }

      guard let currentSession = sessionStore.currentSession else {
        logger.debug("session missing")
        throw AuthError.sessionMissing
      }

      if !currentSession.isExpired {
        return currentSession
      }

      logger.debug("session expired")
      return try await refreshSession(currentSession.refreshToken)
    }
  }

  func refreshSession(_ refreshToken: String) async throws -> Session {
    let logger: Logging.Logger = {
      var scopedLogger = self.logger
      scopedLogger[metadataKey: "refresh_id"] = "\(UUID().uuidString)"
      return scopedLogger
    }()

    return try await trace(using: logger) {
      if let inFlight = inFlightRefreshes[refreshToken] {
        logger.debug("Refresh already in flight")
        return try await inFlight.value
      }

      let refreshTask = Task {
        logger.debug("Refresh task started")

        defer {
          inFlightRefreshes[refreshToken] = nil
          logger.debug("Refresh task ended")
        }

        let fromGeneration = await sessionStore.generation
        let refreshesHeldSession = sessionStore.currentSession?.refreshToken == refreshToken

        let session: Session
        do {
          session = try await api.execute(authAPI.refreshSession(refreshToken: refreshToken))
        } catch let error as AuthError where error.invalidatesSession {
          try? await sessionStore.commit(
            .invalidated(
              SignOutReason(invalidatedBy: error),
              refreshToken: refreshesHeldSession ? refreshToken : nil
            )
          )
          throw error
        }

        try await sessionStore.commit(.refreshed(session, fromGeneration: fromGeneration))
        return session
      }
      inFlightRefreshes[refreshToken] = refreshTask

      return try await refreshTask.value
    }
  }

  func startAutoRefreshToken() {
    logger.debug("start auto refresh token")

    startAutoRefreshTokenTask?.cancel()
    startAutoRefreshTokenTask = Task {
      while !Task.isCancelled {
        await autoRefreshTokenTick()
        try? await clock.sleep(for: .seconds(autoRefreshTickDuration))
      }
    }
  }

  func stopAutoRefreshToken() {
    logger.debug("stop auto refresh token")
    startAutoRefreshTokenTask?.cancel()
    startAutoRefreshTokenTask = nil
  }

  func isAutoRefreshTokenRunning() -> Bool {
    startAutoRefreshTokenTask != nil
  }

  private func autoRefreshTokenTick() async {
    await trace(using: logger) {
      let now = Date().timeIntervalSince1970

      guard let session = sessionStore.currentSession else {
        return
      }

      let expiresInTicks = Int((session.expiresAt - now) / autoRefreshTickDuration)
      logger.debug(
        "access token expires in \(expiresInTicks) ticks, a tick lasts \(autoRefreshTickDuration)s, refresh threshold is \(autoRefreshTickThreshold) ticks"
      )

      if expiresInTicks <= autoRefreshTickThreshold {
        _ = try? await refreshSession(session.refreshToken)
      }
    }
  }
}
