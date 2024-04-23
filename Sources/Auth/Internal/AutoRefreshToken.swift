//
//  AutoRefreshToken.swift
//
//
//  Created by Guilherme Souza on 06/04/24.
//

import _Helpers
import ConcurrencyExtras
import Foundation

actor AutoRefreshToken {
  /// Current session will be checked for refresh at this interval.
  static let tickDuration: TimeInterval = 30
  /// A token refresh will be attempted this many ticks before the current session expires.
  static let tickThreshold = 3

  private var task: Task<Void, Never>?

  @Dependency(\.sessionManager) var sessionManager
  @Dependency(\.logger) var logger

  func start() {
    logger?.debug("")

    task?.cancel()
    task = Task {
      while !Task.isCancelled {
        await autoRefreshTokenTick()
        try? await Task.sleep(nanoseconds: UInt64(AutoRefreshToken.tickDuration) * NSEC_PER_SEC)
      }
    }
  }

  func stop() {
    task?.cancel()
    task = nil
    logger?.debug("")
  }

  private func autoRefreshTokenTick() async {
    logger?.debug("begin")
    defer {
      logger?.debug("end")
    }

    let now = Date()

    do {
      let session = try await sessionManager.session()
      if Task.isCancelled {
        return
      }

      let expiresAt = session.expiresAt

      // session will expire in this many ticks (or has already expired if <= 0)
      let expiresInTicks = Int((expiresAt - now.timeIntervalSince1970) / AutoRefreshToken.tickDuration)

      logger?
        .debug(
          "access token expires in \(expiresInTicks) ticks, a tick last \(AutoRefreshToken.tickDuration)s, refresh threshold is \(AutoRefreshToken.tickThreshold) ticks"
        )

      if expiresInTicks <= AutoRefreshToken.tickThreshold {
        _ = try await sessionManager.refreshSession(session.refreshToken)
      }

    } catch AuthError.sessionNotFound {
      logger?.debug("no session")
      return
    } catch {
      logger?.error("Auto refresh tick failed with error: \(error)")
    }
  }
}
