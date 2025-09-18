import Foundation

struct SessionManager: Sendable {
  var session: @Sendable () async throws -> Session
  var refreshSession: @Sendable (_ refreshToken: String) async throws -> Session
  var update: @Sendable (_ session: Session) async -> Void
  var remove: @Sendable () async -> Void

  var startAutoRefresh: @Sendable () async -> Void
  var stopAutoRefresh: @Sendable () async -> Void
}

extension SessionManager {
  static func live(client: AuthClient) -> Self {
    let instance = LiveSessionManager(client: client)
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
  private var inFlightRefreshTask: Task<Session, any Error>?
  private var startAutoRefreshTokenTask: Task<Void, Never>?

  let client: AuthClient

  init(client: AuthClient) {
    self.client = client
  }

  func session() async throws -> Session {
    try await trace(using: client.configuration.logger) {
      guard let currentSession = await client.sessionStorage.get() else {
        client.configuration.logger?.debug("session missing")
        throw AuthError.sessionMissing
      }

      if !currentSession.isExpired {
        return currentSession
      }

      client.configuration.logger?.debug("session expired")
      return try await refreshSession(currentSession.refreshToken)
    }
  }

  func refreshSession(_ refreshToken: String) async throws -> Session {
    try await trace(using: client.configuration.logger) {
      if let inFlightRefreshTask {
        client.configuration.logger?.debug("Refresh already in flight")
        return try await inFlightRefreshTask.value
      }

      inFlightRefreshTask = Task {
        client.configuration.logger?.debug("Refresh task started")

        defer {
          inFlightRefreshTask = nil
          client.configuration.logger?.debug("Refresh task ended")
        }

        let session = try await client.execute(
          client.url.appendingPathComponent("token"),
          method: .post,
          query: ["grant_type": "refresh_token"],
          body: UserCredentials(refreshToken: refreshToken)
        )
        .serializingDecodable(Session.self, decoder: client.configuration.decoder)
        .value

        await update(session)
        await client.eventEmitter.emit(.tokenRefreshed, session: session)

        return session
      }

      return try await inFlightRefreshTask!.value
    }
  }

  func update(_ session: Session) async {
    await client.sessionStorage.store(session)
  }

  func remove() async {
    await client.sessionStorage.delete()
  }

  func startAutoRefreshToken() {
    client.configuration.logger?.debug("start auto refresh token")

    startAutoRefreshTokenTask?.cancel()
    startAutoRefreshTokenTask = Task {
      while !Task.isCancelled {
        await autoRefreshTokenTick()
        try? await Task.sleep(nanoseconds: NSEC_PER_SEC * UInt64(autoRefreshTickDuration))
      }
    }
  }

  func stopAutoRefreshToken() {
    client.configuration.logger?.debug("stop auto refresh token")
    startAutoRefreshTokenTask?.cancel()
    startAutoRefreshTokenTask = nil
  }

  private func autoRefreshTokenTick() async {
    await trace(using: client.configuration.logger) {
      let now = Date().timeIntervalSince1970

      guard let session = await client.sessionStorage.get() else {
        return
      }

      let expiresInTicks = Int((session.expiresAt - now) / autoRefreshTickDuration)
      client.configuration.logger?.debug(
        "access token expires in \(expiresInTicks) ticks, a tick lasts \(autoRefreshTickDuration)s, refresh threshold is \(autoRefreshTickThreshold) ticks"
      )

      if expiresInTicks <= autoRefreshTickThreshold {
        _ = try? await refreshSession(session.refreshToken)
      }
    }
  }
}
