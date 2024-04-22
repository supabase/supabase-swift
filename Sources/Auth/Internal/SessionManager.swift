import _Helpers
import Foundation

struct SessionManager: Sendable {
  var session: @Sendable (_ shouldValidateExpiration: Bool) async throws -> Session
  var update: @Sendable (_ session: Session) async throws -> Void
  var remove: @Sendable () async -> Void
  var refreshSession: @Sendable (_ refreshToken: String) async throws -> Session
}

extension SessionManager {
  func session(shouldValidateExpiration: Bool = true) async throws -> Session {
    try await session(shouldValidateExpiration)
  }
}

extension SessionManager {
  static let live: SessionManager = {
    let manager = _DefaultSessionManager()

    return SessionManager(
      session: { try await manager.session(shouldValidateExpiration: $0) },
      update: { try await manager.update($0) },
      remove: { await manager.remove() },
      refreshSession: { try await manager.refreshSession($0) }
    )
  }()
}

private actor _DefaultSessionManager {
  private var inFlightRefreshTask: Task<Session, any Error>?

  @Dependency(\.sessionStorage)
  private var storage: SessionStorage

  @Dependency(\.api)
  private var api: APIClient

  @Dependency(\.eventEmitter)
  private var eventEmitter: EventEmitter

  @Dependency(\.logger)
  private var logger

  @Dependency(\.configuration)
  private var configuration

  func session(shouldValidateExpiration _: Bool) async throws -> Session {
    guard var currentSession = try storage.getSession() else {
      throw AuthError.sessionNotFound
    }

    let hasExpired = currentSession.expiresAt <= Date().timeIntervalSince1970
    logger?.debug(
      """
      session has\(hasExpired ? "" : " not") expired
      expires_at = \(currentSession.expiresAt)
      """
    )

    if hasExpired {
      currentSession = try await _callRefreshToken(currentSession.refreshToken)
    }

    return currentSession
  }

  func update(_ session: Session) throws {
    try storage.storeSession(session)
    eventEmitter.emit(.tokenRefreshed, session: session)
  }

  func remove() {
    try? storage.deleteSession()
  }

  func refreshSession(_ refreshToken: String) async throws -> Session {
    try await _callRefreshToken(refreshToken)
  }

  private func _callRefreshToken(_ refreshToken: String) async throws -> Session {
    logger?.debug("being")
    defer { logger?.debug("end") }

    if let inFlightRefreshTask {
      return try await inFlightRefreshTask.value
    }

    inFlightRefreshTask = Task {
      defer { inFlightRefreshTask = nil }

      let session = try await _refreshAccessTokenWithRetry(refreshToken)
      try update(session)
      eventEmitter.emit(.tokenRefreshed, session: session)
      return session
    }

    return try await inFlightRefreshTask!.value
  }

  private func _refreshAccessTokenWithRetry(_ refreshToken: String) async throws -> Session {
    logger?.debug("being")
    defer { logger?.debug("end") }

    let startedAt = Date()

    return try await retry { [logger] attempt in
      if attempt > 0 {
        try await Task.sleep(nanoseconds: NSEC_PER_MSEC * UInt64(200 * pow(2, Double(attempt - 1))))
      }

      logger?.debug("refreshing attempt \(attempt)")

      return try await api.execute(
        Request(
          path: "/token",
          method: .post,
          query: [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
          ],
          body: configuration.encoder.encode(UserCredentials(refreshToken: refreshToken))
        )
      ).decoded(decoder: configuration.decoder)
    } isRetryable: { attempt, error in
      let nextBackoffInterval = 200 * pow(2, Double(attempt))
      return
        isRetryableError(error) &&
        // retryable only if the request can be sent before the backoff overflows the tick duration
        Date().timeIntervalSince1970 + nextBackoffInterval - startedAt.timeIntervalSince1970 < AutoRefreshToken.autoRefreshTickDuration
    }
  }
}
