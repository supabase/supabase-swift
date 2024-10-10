import Foundation
import Helpers

struct SessionManager: Sendable {
  var session: @Sendable () async throws -> Session
  var refreshSession: @Sendable (_ refreshToken: String) async throws -> Session

  var update: @Sendable (_ session: Session) async -> Void
  var remove: @Sendable () async -> Void
}

extension SessionManager {
  static func live(clientID: AuthClientID) -> Self {
    let instance = LiveSessionManager(clientID: clientID)
    return Self(
      session: { try await instance.session() },
      refreshSession: { try await instance.refreshSession($0) },
      update: { await instance.update($0) },
      remove: { await instance.remove() }
    )
  }
}

private actor LiveSessionManager {
  private var configuration: AuthClient.Configuration { Dependencies[clientID].configuration }
  private var sessionStorage: SessionStorage { Dependencies[clientID].sessionStorage }
  private var eventEmitter: AuthStateChangeEventEmitter { Dependencies[clientID].eventEmitter }
  private var logger: (any SupabaseLogger)? { Dependencies[clientID].logger }
  private var api: APIClient { Dependencies[clientID].api }

  private var inFlightRefreshTask: Task<Session, any Error>?
  private var scheduledNextRefreshTask: Task<Void, Never>?

  let clientID: AuthClientID

  init(clientID: AuthClientID) {
    self.clientID = clientID
  }

  func session() async throws -> Session {
    try await trace(using: logger) {
      guard let currentSession = sessionStorage.get() else {
        throw AuthError.sessionMissing
      }

      if !currentSession.isExpired {
        await scheduleNextTokenRefresh(currentSession)

        return currentSession
      }

      return try await refreshSession(currentSession.refreshToken)
    }
  }

  func refreshSession(_ refreshToken: String) async throws -> Session {
    try await SupabaseLoggerTaskLocal.$additionalContext.withValue(
      merging: ["refreshID": .string(UUID().uuidString)]
    ) {
      try await trace(using: logger) {
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
              body: configuration.encoder.encode(
                UserCredentials(refreshToken: refreshToken)
              )
            )
          )
          .decoded(as: Session.self, decoder: configuration.decoder)

          update(session)
          eventEmitter.emit(.tokenRefreshed, session: session)

          await scheduleNextTokenRefresh(session)

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

  private func scheduleNextTokenRefresh(
    _ refreshedSession: Session,
    caller: StaticString = #function
  ) async {
    await SupabaseLoggerTaskLocal.$additionalContext.withValue(
      merging: ["caller": .string("\(caller)")]
    ) {
      guard configuration.autoRefreshToken else {
        logger?.debug("auto refresh token disabled")
        return
      }

      guard scheduledNextRefreshTask == nil else {
        logger?.debug("refresh task already scheduled")
        return
      }

      scheduledNextRefreshTask = Task {
        await trace(using: logger) {
          defer { scheduledNextRefreshTask = nil }

          let expiresAt = Date(timeIntervalSince1970: refreshedSession.expiresAt)
          let expiresIn = expiresAt.timeIntervalSinceNow

          // if expiresIn < 0, it will refresh right away.
          let timeToRefresh = max(expiresIn * 0.9, 0)

          logger?.debug("scheduled next token refresh in: \(timeToRefresh)s")

          try? await Task.sleep(nanoseconds: NSEC_PER_SEC * UInt64(timeToRefresh))

          if Task.isCancelled {
            return
          }

          _ = try? await refreshSession(refreshedSession.refreshToken)
        }
      }
    }
  }
}
