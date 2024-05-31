import _Helpers
import Foundation

struct SessionManager: Sendable {
  var session: @Sendable () async throws -> Session
  var refreshSession: @Sendable (_ refreshToken: String) async throws -> Session

  var update: @Sendable (_ session: Session) async -> Void
  var remove: @Sendable () async -> Void
}

extension SessionManager {
  static var live: Self {
    let instance = LiveSessionManager()
    return Self(
      session: { try await instance.session() },
      refreshSession: { try await instance.refreshSession($0) },
      update: { await instance.update($0) },
      remove: { await instance.remove() }
    )
  }
}

private actor LiveSessionManager {
  private var configuration: AuthClient.Configuration { Current.configuration }
  private var storage: any AuthLocalStorage { Current.configuration.localStorage }
  private var eventEmitter: AuthStateChangeEventEmitter { Current.eventEmitter }
  private var logger: (any SupabaseLogger)? { Current.logger }
  private var api: APIClient { Current.api }

  private var inFlightRefreshTask: Task<Session, any Error>?
  private var scheduledNextRefreshTask: Task<Void, Never>?

  func session() async throws -> Session {
    guard let currentSession = try storage.getSession() else {
      throw AuthError.sessionNotFound
    }

    if !currentSession.isExpired {
      scheduleNextTokenRefresh(currentSession)

      return currentSession
    }

    return try await refreshSession(currentSession.refreshToken)
  }

  func refreshSession(_ refreshToken: String) async throws -> Session {
    logger?.debug("begin")
    defer { logger?.debug("end") }

    if let inFlightRefreshTask {
      logger?.debug("refresh already in flight")
      return try await inFlightRefreshTask.value
    }

    inFlightRefreshTask = Task {
      logger?.debug("refresh task started")

      defer {
        inFlightRefreshTask = nil
        logger?.debug("refresh task ended")
      }

      let session = try await api.execute(
        HTTPRequest(
          url: configuration.url.appendingPathComponent("token"),
          method: .post,
          query: [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
          ],
          body: configuration.encoder.encode(UserCredentials(refreshToken: refreshToken))
        )
      )
      .decoded(as: Session.self, decoder: configuration.decoder)

      update(session)
      eventEmitter.emit(.tokenRefreshed, session: session)

      scheduleNextTokenRefresh(session)

      return session
    }

    return try await inFlightRefreshTask!.value
  }

  func update(_ session: Session) {
    do {
      try storage.storeSession(session)
    } catch {
      logger?.error("Failed to store session: \(error)")
    }
  }

  func remove() {
    do {
      try storage.deleteSession()
    } catch {
      logger?.error("Failed to remove session: \(error)")
    }
  }

  private func scheduleNextTokenRefresh(_ refreshedSession: Session, source: StaticString = #function) {
    logger?.debug("source: \(source)")

    guard configuration.autoRefreshToken else {
      logger?.debug("auto refresh token disabled")
      return
    }

    guard scheduledNextRefreshTask == nil else {
      logger?.debug("source: \(source) refresh task already scheduled")
      return
    }

    scheduledNextRefreshTask = Task {
      defer { scheduledNextRefreshTask = nil }

      let expiresAt = Date(timeIntervalSince1970: refreshedSession.expiresAt)
      let expiresIn = expiresAt.timeIntervalSinceNow

      // if expiresIn < 0, it will refresh right away.
      let timeToRefresh = max(expiresIn * 0.9, 0)

      logger?.debug("source: \(source) scheduled next token refresh in: \(timeToRefresh)s")

      try? await Task.sleep(nanoseconds: NSEC_PER_SEC * UInt64(timeToRefresh))

      if Task.isCancelled {
        return
      }

      _ = try? await refreshSession(refreshedSession.refreshToken)
    }
  }
}
