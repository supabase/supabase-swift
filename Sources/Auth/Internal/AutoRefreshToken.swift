//
//  AutoRefreshToken.swift
//
//
//  Created by Guilherme Souza on 06/04/24.
//

import ConcurrencyExtras
import Foundation

actor AutoRefreshToken {
  private var task: Task<Void, Never>?

  static let autoRefreshTickDuration: TimeInterval = 30
  private let autoRefreshTickThreshold = 3

  @Dependency(\.sessionManager) var sessionManager
  @Dependency(\.logger) var logger

  func start() {
    logger?.debug("")

    task?.cancel()
    task = Task {
      while !Task.isCancelled {
        await autoRefreshTokenTick()
        try? await Task.sleep(nanoseconds: UInt64(Self.autoRefreshTickDuration) * NSEC_PER_SEC)
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
      let expiresInTicks = Int((expiresAt - now.timeIntervalSince1970) / Self.autoRefreshTickDuration)

      logger?
        .debug(
          "access token expires in \(expiresInTicks) ticks, a tick last \(Self.autoRefreshTickDuration)s, refresh threshold is \(autoRefreshTickThreshold) ticks"
        )

      if expiresInTicks <= autoRefreshTickThreshold {
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
