//
//  SessionStorage.swift
//
//
//  Created by Guilherme Souza on 24/10/23.
//

import ConcurrencyExtras
import Foundation
import Logging

struct SessionStorage {
  var get: @Sendable () -> Session?
  var store: @Sendable (_ session: Session) -> Void
  var delete: @Sendable () -> Void
}

extension SessionStorage {
  /// Whether storage no longer holds `snapshot`, what an operation saw stored when it started — a
  /// concurrent sign-out cleared it, another refresh or sign-in replaced it, or a sign-in filled
  /// storage that was empty.
  ///
  /// Callers use this as a commit guard: a request that outlived the session it was issued for
  /// must not apply its result to whichever session is stored now. The comparison is between two
  /// storage reads, not between a caller's input and storage, because a `nil` snapshot is
  /// legitimate — `setSession(accessToken:refreshToken:)` refreshes an externally-sourced token
  /// with nothing stored yet. That is a hydration only for as long as storage stays empty; once
  /// another sign-in lands, the hydration is the stale one.
  func changed(since snapshot: Session?) -> Bool {
    get()?.refreshToken != snapshot?.refreshToken
  }

  /// Key used to store session on ``AuthLocalStorage``.
  ///
  /// It uses value from ``AuthClient/Configuration/storageKey`` or default to `supabase.auth.token` if not provided.
  static func key(_ configuration: AuthClient.Configuration) -> String {
    configuration.storageKey ?? defaultStorageKey
  }

  /// Reads and writes through ``PersistedSessionCodec``, so it writes schema 1.
  ///
  /// It mirrors ``PersistedSessionLoader`` over the synchronous ``AuthLocalStorage``: a v2 format
  /// is rewritten the first time it is read, and the legacy key is checked once per instance.
  static func live(configuration: AuthClient.Configuration) -> SessionStorage {
    let storage = configuration.localStorage
    let logger = configuration.logger
    let key = SessionStorage.key(configuration)
    let legacyKeyPending = LockIsolated(true)

    return SessionStorage(
      get: {
        do {
          if let data = try storage.retrieve(key: key) {
            let decoded = try PersistedSessionCodec.decode(data)
            if !decoded.isCurrentSchema {
              do {
                try storage.store(key: key, value: PersistedSessionCodec.encode(decoded.session))
              } catch {
                logger.error("Failed to migrate stored session: \(error.localizedDescription)")
              }
            }
            return decoded.session.session
          }

          return try legacyKeyPending.withValue { pending in
            guard pending else { return nil }
            var session: Session?
            if let legacyData = try storage.retrieve(key: PersistedSessionLoader.legacyKey) {
              let decoded = try PersistedSessionCodec.decode(legacyData)
              try storage.store(key: key, value: PersistedSessionCodec.encode(decoded.session))
              try storage.remove(key: PersistedSessionLoader.legacyKey)
              session = decoded.session.session
            }
            pending = false
            return session
          }
        } catch {
          logger.error("Failed to retrieve session: \(error.localizedDescription)")
          return nil
        }
      },
      store: { session in
        // Callers also store a session whose user changed, so "now" is not its receipt time.
        do {
          try storage.store(
            key: key,
            value: PersistedSessionCodec.encode(ReceivedSession(session: session))
          )
        } catch {
          logger.error("Failed to store session: \(error.localizedDescription)")
        }
      },
      delete: {
        do {
          try storage.remove(key: key)
        } catch {
          logger.error("Failed to delete session: \(error.localizedDescription)")
        }
      }
    )
  }
}
