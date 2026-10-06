import Clocks
import ConcurrencyExtras
import Foundation
import HTTPTypes
import Logging

/// Which stored session a request may clear when the server says the session it was issued for
/// is gone.
enum SessionOwnership: Sendable {
  /// The request was issued for no particular stored session — sign-in, sign-up, `/logout`.
  /// Cleanup clears whatever is stored, as it always has.
  case unscoped
  /// The stored session the request was issued for, read before the request went out; `nil` when
  /// storage was empty then. Cleanup clears storage only while it still holds exactly this, so a
  /// request that outlived a sign-out cannot sign out whoever signed in after it.
  case snapshot(Session?)
}

struct SessionManager: Sendable {
  var session: @Sendable () async throws -> Session
  var refreshSession: @Sendable (_ refreshToken: String) async throws -> Session
  var update: @Sendable (_ session: Session) async -> Void
  var remove: @Sendable () async -> Void
  /// Deletes the stored session only while `ownership` still covers it. Returns whether it
  /// deleted, so the caller emits `.signedOut` for a sign-out that actually happened.
  var removeIfUnchanged: @Sendable (_ ownership: SessionOwnership) async -> Bool

  var startAutoRefresh: @Sendable () async -> Void
  var stopAutoRefresh: @Sendable () async -> Void

  /// Whether the auto-refresh loop is currently scheduled.
  var isAutoRefreshRunning: @Sendable () async -> Bool
}

extension SessionManager {
  static func live(
    configuration: AuthClient.Configuration,
    api: APIClient,
    sessionStorage: SessionStorage,
    eventEmitter: AuthStateChangeEventEmitter,
    logger: Logging.Logger
  ) -> Self {
    let instance = LiveSessionManager(
      configuration: configuration,
      api: api,
      sessionStorage: sessionStorage,
      eventEmitter: eventEmitter,
      logger: logger
    )
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
  private let configuration: AuthClient.Configuration
  private let api: APIClient
  private let sessionStorage: SessionStorage
  private let eventEmitter: AuthStateChangeEventEmitter
  private let logger: Logging.Logger

  private var clock: any Clock<Duration> { configuration.clock }

  // Keyed by the refresh token each task was started for: a refresh asked for a different token
  // is a different operation and must not be served another's result, while a second request for
  // the same token joins the one already in flight instead of redeeming it twice.
  private var inFlightRefreshes: [String: Task<Session, any Error>] = [:]
  private var startAutoRefreshTokenTask: Task<Void, Never>?

  init(
    configuration: AuthClient.Configuration,
    api: APIClient,
    sessionStorage: SessionStorage,
    eventEmitter: AuthStateChangeEventEmitter,
    logger: Logging.Logger
  ) {
    self.configuration = configuration
    self.api = api
    self.sessionStorage = sessionStorage
    self.eventEmitter = eventEmitter
    self.logger = logger
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
      do {
        return try await refreshSession(currentSession.refreshToken)
      } catch let error as AuthError {
        // Another client sharing this storage (an app extension, a second client in the same
        // process) may have rotated the same token first and stored its session, so this refresh
        // was discarded by the commit guard or rejected by the server as already used. Storage is
        // the source of truth then. Empty storage (a concurrent sign-out) or an expired stored
        // session means the session is gone and the error stands.
        if let stored = sessionStorage.get(), !stored.isExpired {
          logger.debug("Refresh failed, returning the session stored meanwhile")
          return stored
        }
        throw error
      }
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

        let session: Session
        do {
          session = try await api.execute(
            HTTPRequest(
              method: .post,
              url: configuration.url.appendingPathComponent("token"),
              query: [
                URLQueryItem(name: "grant_type", value: "refresh_token")
              ]
            ),
            body: configuration.resolvedEncoder.encode(
              UserCredentials(refreshToken: refreshToken)
            )
          )
          .decoded(as: Session.self, decoder: configuration.resolvedDecoder)
        } catch let error as AuthError where error.invalidatesSession {
          // The server rejected `refreshToken`, so only the stored session that token belongs to
          // is gone. A token storage never held — a `setSession` hydration, or one a caller
          // passed to `refreshSession(refreshToken:)` — owns nothing stored, so whichever session
          // is stored must not be signed out on its behalf.
          let owned = storedAtStart?.refreshToken == refreshToken ? storedAtStart : nil
          if removeIfUnchanged(since: .snapshot(owned)) {
            eventEmitter.emit(.signedOut, session: nil)
          }
          throw error
        }

        // The rotated tokens replace `storedAtStart`. If that session was signed out, or replaced
        // by another user signing in, while this request was in flight, committing them would
        // hand the next user the previous user's session. Drop them instead.
        //
        // Only the success path needs this. The failure path above clears storage itself when the
        // server says the session is gone, so a check there could not tell that apart from a
        // concurrent sign-out.
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

  /// Deletes the stored session, but only while `ownership` still covers it.
  ///
  /// The check and the delete are one actor-isolated step with no suspension between them. A
  /// caller that read storage itself and then awaited `remove()` would leave a window for a
  /// concurrent sign-in to store its session and have this deletion take it.
  func removeIfUnchanged(since ownership: SessionOwnership) -> Bool {
    if case .snapshot(let snapshot) = ownership, sessionStorage.changed(since: snapshot) {
      return false
    }
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
