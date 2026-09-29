import Clocks
import ConcurrencyExtras
import Foundation
import HTTPTypes
import Logging

struct SessionManager: Sendable {
  var session: @Sendable () async throws -> Session
  var refreshSession: @Sendable (_ refreshToken: String) async throws -> Session
  var update: @Sendable (_ session: Session) async -> Void
  var remove: @Sendable () async -> Void
  /// Deletes the stored session only while storage still holds `snapshot`. Returns whether it
  /// deleted, so the caller emits `.signedOut` for a sign-out that actually happened.
  var removeIfUnchanged: @Sendable (_ snapshot: Session?) async -> Bool

  var startAutoRefresh: @Sendable () async -> Void
  var stopAutoRefresh: @Sendable () async -> Void

  /// Whether the auto-refresh loop is currently scheduled.
  var isAutoRefreshRunning: @Sendable () async -> Bool
}

extension SessionManager {
  static func live(clientID: AuthClientID) -> Self {
    let instance = LiveSessionManager(clientID: clientID)
    return Self(
      session: { try await instance.session() },
      refreshSession: { try await instance.refreshSession($0) },
      update: { await instance.update($0) },
      remove: { await instance.remove() },
      removeIfUnchanged: { await instance.removeIfUnchanged(since: $0) },
      startAutoRefresh: { await instance.startAutoRefreshToken() },
      stopAutoRefresh: { await instance.stopAutoRefreshToken() },
      isAutoRefreshRunning: { await instance.isAutoRefreshTokenRunning() }
    )
  }
}

private actor LiveSessionManager {
  private var configuration: AuthClient.Configuration { Dependencies[clientID].configuration }
  private var sessionStorage: SessionStorage { Dependencies[clientID].sessionStorage }
  private var eventEmitter: AuthStateChangeEventEmitter { Dependencies[clientID].eventEmitter }
  // Looked up leniently, as the session manager outlives its client while the auto-refresh loop is
  // torn down from `AuthClient.deinit`, at which point the dependencies entry is already gone.
  private var logger: Logging.Logger {
    Dependencies.instances.value[clientID]?.logger
      ?? supabaseDefaultLogger(label: "io.supabase.auth")
  }
  private var api: APIClient { Dependencies[clientID].api }
  // Looked up leniently for the same reason as `logger` above: the auto-refresh loop can
  // outlive its client's dependencies entry.
  private var clock: any Clock<Duration> {
    Dependencies.instances.value[clientID]?.configuration.clock ?? ContinuousClock()
  }

  // Keyed by the refresh token each task was started for: a refresh asked for a different token
  // is a different operation and must not be served another's result, while a second request for
  // the same token joins the one already in flight instead of redeeming it twice.
  private var inFlightRefreshes: [String: Task<Session, any Error>] = [:]
  private var startAutoRefreshTokenTask: Task<Void, Never>?

  let clientID: AuthClientID

  init(clientID: AuthClientID) {
    self.clientID = clientID
  }

  func session() async throws -> Session {
    try await trace(using: logger) {
      guard let currentSession = sessionStorage.get() else {
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
    // Read before any suspension point, so a `signOut` cannot land between entering the actor and
    // this read and leave the commit guard below with nothing to compare against.
    let storedAtStart = sessionStorage.get()

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

      // Held in a local as well as the property, so awaiting it does not mean re-reading a
      // property the task itself clears in its `defer`.
      let refreshTask = Task {
        logger.debug("Refresh task started")

        defer {
          inFlightRefreshes[refreshToken] = nil
          logger.debug("Refresh task ended")
        }

        let session = try await api.execute(
          HTTPRequest(
            method: .post,
            url: configuration.url.appendingPathComponent("token"),
            query: [
              URLQueryItem(name: "grant_type", value: "refresh_token")
            ]
          ),
          body: configuration.resolvedEncoder.encode(
            UserCredentials(refreshToken: refreshToken)
          ),
          for: storedAtStart
        )
        .decoded(as: Session.self, decoder: configuration.resolvedDecoder)

        // The rotated tokens belong to `storedAtStart`. If that session was signed out, or
        // replaced by another user signing in, while this request was in flight, committing them
        // would hand the next user the previous user's session. Drop them instead.
        //
        // Only the success path needs this. A failure has already been through
        // `APIClient.handleError(response:data:for:)`, which scopes its own cleanup to
        // `storedAtStart` — and which clears storage itself when the cleanup is legitimate, so a
        // check here could not tell that apart from a concurrent sign-out.
        if sessionStorage.changed(since: storedAtStart) {
          logger.debug("Refresh discarded: the session it started from is no longer stored")
          throw AuthError.refreshDiscarded
        }

        update(session)
        eventEmitter.emit(.tokenRefreshed, session: session)

        return session
      }
      inFlightRefreshes[refreshToken] = refreshTask

      return try await refreshTask.value
    }
  }

  func update(_ session: Session) {
    sessionStorage.store(session)
  }

  func remove() {
    sessionStorage.delete()
  }

  /// Deletes the stored session, but only while storage still holds `snapshot` — the session the
  /// caller's request was scoped to.
  ///
  /// The check and the delete are one actor-isolated step with no suspension between them. A
  /// caller that read storage itself and then awaited `remove()` would leave a window for a
  /// concurrent sign-in to store its session and have this deletion take it.
  func removeIfUnchanged(since snapshot: Session?) -> Bool {
    guard !sessionStorage.changed(since: snapshot) else { return false }
    sessionStorage.delete()
    return true
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

      guard let session = sessionStorage.get() else {
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
