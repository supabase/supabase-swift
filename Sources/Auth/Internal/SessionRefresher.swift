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

  private var configuration: AuthClient.Configuration {
    Current.configuration
  }

  private var storage: any AuthLocalStorage {
    Current.configuration.localStorage
  }

  private var eventEmitter: AuthStateChangeEventEmitter {
    Current.eventEmitter
  }

  private var logger: (any SupabaseLogger)? {
    Current.logger
  }

  private var api: APIClient {
    Current.api
  }

  private var task: Task<Session, any Error>?

  func refreshSession(_ refreshToken: String) async throws -> Session {
    logger?.debug("begin")
    defer { logger?.debug("end") }

    if let task {
      return try await task.value
    }

    task = Task {
      defer { task = nil }

      let session = try await refreshSessionWithRetry(refreshToken)
      try storage.storeSession(StoredSession(session: session))
      eventEmitter.emit(.tokenRefreshed, session: session)
      return session
    }

    return try await task!.value
  }

  private func refreshSessionWithRetry(_ refreshToken: String) async throws -> Session {
    logger?.debug("begin")
    defer { logger?.debug("end") }

    let startedAt = Date()

    return try await retry { [logger] attempt in
      if attempt > 0 {
        try await Task.sleep(nanoseconds: NSEC_PER_MSEC * UInt64(200 * pow(2, Double(attempt - 1))))
      }

      logger?.debug("refreshing attempt \(attempt)")

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
      let nextBackoffInterval = 200 * pow(2, Double(attempt))
      return isRetryableError(error) &&
        Date().timeIntervalSince1970 + nextBackoffInterval - startedAt.timeIntervalSince1970 < AUTO_REFRESH_TICK_DURATION
    }
  }
}
