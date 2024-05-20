//
//  AutoRefreshToken.swift
//
//
//  Created by Guilherme Souza on 20/05/24.
//

import _Helpers
import Foundation

struct AutoRefreshToken: Sendable {
  var start: @Sendable () async -> Void
  var stop: @Sendable () async -> Void
}

extension AutoRefreshToken {
  static var live: Self {
    let instance = LiveAutoRefreshToken.shared
    return Self(
      start: { await instance.start() },
      stop: { await instance.stop() }
    )
  }
}

private actor LiveAutoRefreshToken {
  static let shared = LiveAutoRefreshToken()

  private var sessionRefresher: SessionRefresher { Current.sessionRefresher }
  private var storage: any AuthLocalStorage { Current.configuration.localStorage }
  private var logger: (any SupabaseLogger)? { Current.logger }
  private var autoRefreshTokenTask: Task<Void, Never>?

  func start() {
    logger?.debug("")

    guard autoRefreshTokenTask == nil else { return }

    autoRefreshTokenTask = Task {
      defer { autoRefreshTokenTask = nil }

      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: UInt64(AUTO_REFRESH_TICK_DURATION) * NSEC_PER_SEC)
        await autoRefreshTokenTick()
      }
    }
  }

  func stop() {
    logger?.debug("")

    autoRefreshTokenTask?.cancel()
    autoRefreshTokenTask = nil
  }

  private func autoRefreshTokenTick() async {
    logger?.debug("begin")
    defer {
      logger?.debug("end")
    }

    let now = Date()

    do {
      guard let currentSession = try? storage.getSession() else {
        throw AuthError.sessionNotFound
      }

      let expiresAt = currentSession.expiresAt

      // session will expire in this many ticks (or has already expired if <= 0)
      let expiresInTicks = Int((expiresAt - now.timeIntervalSince1970) / AUTO_REFRESH_TICK_DURATION)

      logger?
        .debug(
          "access token expires in \(expiresInTicks) ticks, a tick last \(AUTO_REFRESH_TICK_DURATION)s, refresh threshold is \(AUTO_REFRESH_TICK_THRESHOLD) ticks"
        )

      if expiresInTicks <= AUTO_REFRESH_TICK_THRESHOLD {
        _ = try await sessionRefresher.refreshSession(currentSession.refreshToken)
      }

    } catch AuthError.sessionNotFound {
      logger?.debug("no session")
      return
    } catch {
      logger?.error("Auto refresh tick failed with error: \(error)")
    }
  }
}
