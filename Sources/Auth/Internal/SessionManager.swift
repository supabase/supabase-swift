import Foundation
import HTTPTypes

struct SessionManager: Sendable {
  var session: @Sendable () async throws -> Session
  var refreshSession: @Sendable (_ refreshToken: String) async throws -> Session
  var update: @Sendable (_ session: Session) async -> Void
  var remove: @Sendable () async -> Void

  var startAutoRefresh: @Sendable () async -> Void
  var stopAutoRefresh: @Sendable () async -> Void
}

extension SessionManager {
  static func live(dependencies: DependenciesContainer) -> Self {
    let instance = LiveSessionManager(dependencies: dependencies)
    return Self(
      session: { try await instance.session() },
      refreshSession: { try await instance.refreshSession($0) },
      update: { await instance.update($0) },
      remove: { await instance.remove() },
      startAutoRefresh: { await instance.startAutoRefreshToken() },
      stopAutoRefresh: { await instance.stopAutoRefreshToken() }
    )
  }
}

private actor LiveSessionManager {
  private var configuration: AuthClient.Configuration { dependencies.value.configuration }
  private var sessionStorage: SessionStorage { dependencies.value.sessionStorage }
  private var eventEmitter: AuthStateChangeEventEmitter { dependencies.value.eventEmitter }
  private var logger: (any SupabaseLogger)? { dependencies.value.logger }
  private var api: APIClient { dependencies.value.api }

  private var inFlightRefreshTask: Task<Session, any Error>?
  private var startAutoRefreshTokenTask: Task<Void, Never>?

  let dependencies: DependenciesContainer

  init(dependencies: DependenciesContainer) {
    self.dependencies = dependencies
  }

  func session() async throws -> Session {
    try await trace(using: logger) {
      guard let currentSession = sessionStorage.get() else {
        logger?.debug("session missing")
        throw AuthError.sessionMissing
      }

      if !currentSession.isExpired {
        return currentSession
      }

      logger?.debug("session expired")
      return try await refreshSession(currentSession.refreshToken)
    }
  }

  func refreshSession(_ refreshToken: String) async throws -> Session {
    try await SupabaseLoggerTaskLocal.$additionalContext.withValue(
      merging: [
        "refresh_id": .string(UUID().uuidString),
        "refresh_token": .string(refreshToken),
      ]
    ) {
      try await trace(using: logger) {
        if let inFlightRefreshTask {
          logger?.debug("Refresh already in flight")
          return try await inFlightRefreshTask.value
        }

        inFlightRefreshTask = Task {
          logger?.debug("Refresh task started")

          defer {
            inFlightRefreshTask = nil
            logger?.debug("Refresh task ended")
          }

          let session = try await api.execute(
            HTTPRequest(
              url: configuration.url.appendingPathComponent("token"),
              method: .post,
              query: [
                URLQueryItem(name: "grant_type", value: "refresh_token")
              ],
              body: configuration.resolvedEncoder.encode(
                UserCredentials(refreshToken: refreshToken)
              )
            )
          )
          .decoded(as: Session.self, decoder: configuration.resolvedDecoder)

          update(session)
          eventEmitter.emit(.tokenRefreshed, session: session)

          return session
        }

        return try await inFlightRefreshTask!.value
      }
    }
  }

  func update(_ session: Session) {
    sessionStorage.store(session)
  }

  func remove() {
    sessionStorage.delete()
  }

  func startAutoRefreshToken() {
    logger?.debug("start auto refresh token")

    startAutoRefreshTokenTask?.cancel()
    startAutoRefreshTokenTask = Task {
      while !Task.isCancelled {
        await autoRefreshTokenTick()
        try? await Task.sleep(nanoseconds: NSEC_PER_SEC * UInt64(autoRefreshTickDuration))
      }
    }
  }

  func stopAutoRefreshToken() {
    logger?.debug("stop auto refresh token")
    startAutoRefreshTokenTask?.cancel()
    startAutoRefreshTokenTask = nil
  }

  private func autoRefreshTokenTick() async {
    await trace(using: logger) {
      let now = Date().timeIntervalSince1970

      guard let session = sessionStorage.get() else {
        return
      }

      let expiresInTicks = Int((session.expiresAt - now) / autoRefreshTickDuration)
      logger?.debug(
        "access token expires in \(expiresInTicks) ticks, a tick lasts \(autoRefreshTickDuration)s, refresh threshold is \(autoRefreshTickThreshold) ticks"
      )

      if expiresInTicks <= autoRefreshTickThreshold {
        _ = try? await refreshSession(session.refreshToken)
      }
    }
  }
}
