//
//  SessionStateMachine.swift
//  Auth
//
//  Created by Guilherme Souza on 23/03/26.
//

import Foundation

enum SessionState: Sendable {
  /// Initial state before persistent storage has been read.
  case uninitialized
  case unauthenticated
  case authenticated(Session)
  case refreshing(session: Session, task: Task<Session, any Error>)
}

actor SessionStateMachine {
  private var state: SessionState = .uninitialized

  private var autoRefreshTask: Task<Void, Never>?

  private var configuration: AuthClient.Configuration { Dependencies[clientID].configuration }
  private var sessionStorage: SessionStorage { Dependencies[clientID].sessionStorage }
  private var eventEmitter: AuthStateChangeEventEmitter { Dependencies[clientID].eventEmitter }
  private var logger: (any SupabaseLogger)? { Dependencies[clientID].logger }
  private var api: APIClient { Dependencies[clientID].api }

  let clientID: AuthClientID

  init(clientID: AuthClientID) {
    self.clientID = clientID
  }

  // MARK: - Public interface

  /// Returns a valid session, refreshing it automatically if expired.
  func validSession() async throws -> Session {
    if case .uninitialized = state {
      loadFromStorage()
    }

    return try await trace(using: logger) {
      switch state {
      case .uninitialized:
        preconditionFailure("State must be initialized before reaching switch")

      case .unauthenticated:
        logger?.debug("session missing")
        throw AuthError.sessionMissing

      case .authenticated(let session) where !session.isExpired:
        return session

      case .authenticated(let session):
        logger?.debug("session expired")
        return try await refresh(token: session.refreshToken)

      case .refreshing(_, let task):
        logger?.debug("Refresh already in flight")
        return try await task.value
      }
    }
  }

  /// Forces a token refresh with the given refresh token.
  ///
  /// If a refresh is already in flight, this method coalesces with it and returns the same result.
  /// Emits a `.tokenRefreshed` event on success.
  func refresh(token: String) async throws -> Session {
    if case .uninitialized = state {
      loadFromStorage()
    }

    return try await SupabaseLoggerTaskLocal.$additionalContext.withValue(
      merging: [
        "refresh_id": .string(UUID().uuidString),
        "refresh_token": .string(token),
      ]
    ) {
      try await trace(using: logger) {
        // Coalesce with any in-flight refresh.
        if case .refreshing(_, let existingTask) = state {
          logger?.debug("Refresh already in flight, coalescing")
          return try await existingTask.value
        }

        let refreshTask = Task<Session, any Error> {
          logger?.debug("Refresh task started")
          defer { logger?.debug("Refresh task ended") }
          return try await self.performRefresh(token: token)
        }

        // Transition to refreshing state, preserving current session for reads during refresh.
        // When unauthenticated (e.g., explicit refresh with an external token), skip the transition
        // since there's no current session to preserve.
        if case .authenticated(let session) = state {
          state = .refreshing(session: session, task: refreshTask)
        }

        do {
          let newSession = try await refreshTask.value
          update(newSession)
          eventEmitter.emit(.tokenRefreshed, session: newSession)
          return newSession
        } catch {
          if !(error is CancellationError) {
            state = .unauthenticated
          }
          throw error
        }
      }
    }
  }

  func update(_ session: Session) {
    sessionStorage.store(session)
    state = .authenticated(session)
  }

  func remove() {
    if case .refreshing(_, let task) = state {
      task.cancel()
    }
    sessionStorage.delete()
    state = .unauthenticated
  }

  func startAutoRefresh() {
    logger?.debug("start auto refresh token")
    autoRefreshTask?.cancel()
    autoRefreshTask = Task {
      while !Task.isCancelled {
        await autoRefreshTokenTick()
        try? await Task.sleep(nanoseconds: NSEC_PER_SEC * UInt64(autoRefreshTickDuration))
      }
    }
  }

  func stopAutoRefresh() {
    logger?.debug("stop auto refresh token")
    autoRefreshTask?.cancel()
    autoRefreshTask = nil
  }

  // MARK: - Private helpers

  /// Loads session from persistent storage and transitions out of the `.uninitialized` state.
  private func loadFromStorage() {
    if let stored = sessionStorage.get() {
      state = .authenticated(stored)
    } else {
      state = .unauthenticated
    }
  }

  private func performRefresh(token: String) async throws -> Session {
    try await api.execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("token"),
        method: .post,
        query: [
          URLQueryItem(name: "grant_type", value: "refresh_token")
        ],
        body: configuration.encoder.encode(
          UserCredentials(refreshToken: token)
        )
      )
    )
    .decoded(as: Session.self, decoder: configuration.decoder)
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
        _ = try? await validSession()
      }
    }
  }
}
