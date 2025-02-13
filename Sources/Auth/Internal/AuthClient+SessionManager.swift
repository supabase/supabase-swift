import Foundation
import Helpers

extension AuthClient {

  func _session() async throws -> Session {
    try await trace(using: logger) {
      guard let currentSession = getStoredSession() else {
        logger?.debug("session missing")
        throw AuthError.sessionMissing
      }

      if !currentSession.isExpired {
        return currentSession
      }

      logger?.debug("session expired")
      return try await _refreshSession(currentSession.refreshToken)
    }
  }

  func _refreshSession(_ refreshToken: String) async throws -> Session {
    try await SupabaseLoggerTaskLocal.$additionalContext.withValue(
      merging: [
        "refresh_id": .string(UUID().uuidString),
        "refresh_token": .string(refreshToken),
      ]
    ) {
      try await trace(using: logger) {
        if let inFlightRefreshTask = mutableState.inFlightRefreshTask {
          logger?.debug("Refresh already in flight")
          return try await inFlightRefreshTask.value
        }

        let inFlightRefreshTask = Task {
          logger?.debug("Refresh task started")

          defer {
            mutableState.withValue {
              $0.inFlightRefreshTask = nil
            }
            logger?.debug("Refresh task ended")
          }

          do {
            let session = try await execute(
              HTTPRequest(
                url: configuration.url.appendingPathComponent("token"),
                method: .post,
                query: [
                  URLQueryItem(name: "grant_type", value: "refresh_token")
                ],
                body: configuration.encoder.encode(
                  UserCredentials(refreshToken: refreshToken)
                )
              )
            )
            .decoded(as: Session.self, decoder: configuration.decoder)

            storeSession(session)
            eventEmitter.emit(.tokenRefreshed, session: session)

            return session
          } catch {
            logger?.debug("Refresh token failed with error: \(error)")

            // DO NOT remove session in case it is an error that should be retried.
            // i.e. server instability, connection issues, ...
            //
            // Need to do this check here, because not all RetryableError's should be retried.
            // URLError conforms to RetryableError, but only a subset of URLError should be retried,
            // the same is true for AuthError.
            if let error = error as? URLError, error.shouldRetry {
              throw error
            } else if let error = error as? any RetryableError, error.shouldRetry {
              throw error
            } else {
              deleteSession()
              throw error
            }
          }
        }

        mutableState.withValue {
          $0.inFlightRefreshTask = inFlightRefreshTask
        }

        return try await inFlightRefreshTask.value
      }
    }
  }

  //  func update(_ session: Session) {
  //    client.storeSession(session)
  //  }

  //  func remove() {
  //    client.deleteSession()
  //  }

  func _startAutoRefreshToken() {
    logger?.debug("start auto refresh token")

    mutableState.withValue {
      $0.autoRefreshTokenTask?.cancel()
      $0.autoRefreshTokenTask = Task {
        while !Task.isCancelled {
          await autoRefreshTokenTick()
          try? await Task.sleep(nanoseconds: NSEC_PER_SEC * UInt64(autoRefreshTickDuration))
        }
      }
    }
  }

  func _stopAutoRefreshToken() {
    logger?.debug("stop auto refresh token")

    mutableState.withValue {
      $0.autoRefreshTokenTask?.cancel()
      $0.autoRefreshTokenTask = nil
    }
  }

  private func autoRefreshTokenTick() async {
    await trace(using: logger) {
      let now = Date().timeIntervalSince1970

      guard let session = getStoredSession() else {
        return
      }

      let expiresInTicks = Int((session.expiresAt - now) / autoRefreshTickDuration)
      logger?.debug(
        "access token expires in \(expiresInTicks) ticks, a tick lasts \(autoRefreshTickDuration)s, refresh threshold is \(autoRefreshTickThreshold) ticks"
      )

      if expiresInTicks <= autoRefreshTickThreshold {
        _ = try? await _refreshSession(session.refreshToken)
      }
    }
  }
}
