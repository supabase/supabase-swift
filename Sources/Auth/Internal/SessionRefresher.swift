//
//  SessionRefresher.swift
//
//
//  Created by Guilherme Souza on 20/05/24.
//

import _Helpers
import Foundation

struct SessionRefresher: Sendable {
  var refreshSession: @Sendable (_ refreshToken: String) async throws -> Session
}

extension SessionRefresher {
  static var live: Self {
    let instance = LiveSessionRefresher.shared
    return SessionRefresher {
      try await instance.refreshSession($0)
    }
  }
}

private actor LiveSessionRefresher {
  static let shared = LiveSessionRefresher()

  private var configuration: AuthClient.Configuration { Current.configuration }
  private var storage: any AuthLocalStorage { Current.configuration.localStorage }
  private var eventEmitter: AuthStateChangeEventEmitter { Current.eventEmitter }
  private var logger: (any SupabaseLogger)? { Current.logger }
  private var api: APIClient { Current.api }

  private var inFlightRefreshTask: Task<Session, any Error>?
  private var scheduledNextRefreshTask: Task<Void, Never>?

  func refreshSession(_ refreshToken: String) async throws -> Session {
    logger?.debug("begin")
    defer { logger?.debug("end") }

    if let inFlightRefreshTask {
      return try await inFlightRefreshTask.value
    }

    inFlightRefreshTask = Task {
      defer { inFlightRefreshTask = nil }

      let session = try await refreshSessionWithRetry(refreshToken)
      try storage.storeSession(session)
      eventEmitter.emit(.tokenRefreshed, session: session)

      scheduleNextTokenRefresh(session)

      return session
    }

    return try await inFlightRefreshTask!.value
  }

  private func refreshSessionWithRetry(_ refreshToken: String) async throws -> Session {
    logger?.debug("begin")
    defer { logger?.debug("end") }

    let startedAt = Date()

    return try await retry { [logger] attempt in
      if attempt > 0 {
        try await Task.sleep(
          nanoseconds: NSEC_PER_MSEC * UInt64(computeRetryDelay(attempt: attempt - 1))
        )
      }

      logger?.debug("refresh attempt \(attempt)")

      return try await api.execute(
        HTTPRequest(
          url: configuration.url.appendingPathComponent("token"),
          method: .post,
          query: [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
          ],
          body: configuration.encoder.encode(UserCredentials(refreshToken: refreshToken))
        )
      ).decoded(decoder: configuration.decoder)
    } isRetryable: { attempt, error in
      let nextBackoffInterval = computeRetryDelay(attempt: attempt)
      return error.isRetryable &&
        Date().timeIntervalSince1970 + nextBackoffInterval - startedAt.timeIntervalSince1970 < AUTO_REFRESH_TICK_DURATION
    }
  }

  private func scheduleNextTokenRefresh(_ refreshedSession: Session) {
    logger?.debug("")

    guard scheduledNextRefreshTask == nil else {
      return
    }

    scheduledNextRefreshTask = Task {
      defer { scheduledNextRefreshTask = nil }

      let expiresAt = Date(timeIntervalSince1970: refreshedSession.expiresAt)
      let expiresIn = expiresAt.timeIntervalSinceNow

      // if expiresIn < 0, it will refresh right away.
      let timeToRefresh = max(expiresIn * 0.9, 0)

      logger?.debug("scheduled next token refresh in: \(timeToRefresh)s")

      try? await Task.sleep(nanoseconds: NSEC_PER_SEC * UInt64(timeToRefresh))

      _ = try? await refreshSession(refreshedSession.refreshToken)
    }
  }

  private nonisolated func computeRetryDelay(attempt: Int) -> TimeInterval {
    200 * pow(2, Double(attempt))
  }
}
