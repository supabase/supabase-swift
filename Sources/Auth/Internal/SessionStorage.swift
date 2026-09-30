//
//  SessionStorage.swift
//
//
//  Created by Guilherme Souza on 24/10/23.
//

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

  static func live(configuration: AuthClient.Configuration) -> SessionStorage {
    let storage = configuration.localStorage
    let logger = configuration.logger

    let migrations: [StorageMigration] = [
      .sessionNewKey(configuration: configuration),
      .storeSessionDirectly(configuration: configuration),
      .useDefaultEncoder(configuration: configuration),
    ]

    let key = SessionStorage.key(configuration)

    return SessionStorage(
      get: {
        for migration in migrations {
          do {
            try migration.run()
          } catch {
            logger.error(
              "Storage migration '\(migration.name)' failed: \(error.localizedDescription)"
            )
          }
        }

        do {
          let storedData = try storage.retrieve(key: key)
          return try storedData.flatMap {
            try JSONDecoder().decode(Session.self, from: $0)
          }
        } catch {
          logger.error("Failed to retrieve session: \(error.localizedDescription)")
          return nil
        }
      },
      store: { session in
        do {
          try storage.store(
            key: key,
            value: JSONEncoder().encode(session)
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

struct StorageMigration {
  var name: String
  var run: @Sendable () throws -> Void
}

extension StorageMigration {
  /// Migrate stored session from `supabase.session` key to the custom provided storage key
  /// or the default `supabase.auth.token` key.
  static func sessionNewKey(configuration: AuthClient.Configuration) -> StorageMigration {
    StorageMigration(name: "sessionNewKey") {
      let storage = configuration.localStorage
      let newKey = SessionStorage.key(configuration)

      if let storedData = try? storage.retrieve(key: "supabase.session") {
        try storage.store(key: newKey, value: storedData)
        try? storage.remove(key: "supabase.session")
      }
    }
  }

  /// Migrate the stored session.
  ///
  /// Migrate the stored session which used to be stored as:
  /// ```json
  /// {
  ///   "session": <Session>,
  ///   "expiration_date": <Date>
  /// }
  /// ```
  /// To directly store the `Session` object.
  static func storeSessionDirectly(configuration: AuthClient.Configuration) -> StorageMigration {
    struct StoredSession: Codable {
      var session: Session
      var expirationDate: Date
    }

    return StorageMigration(name: "storeSessionDirectly") {
      let storage = configuration.localStorage
      let key = SessionStorage.key(configuration)

      if let data = try? storage.retrieve(key: key),
        let storedSession = try? AuthClient.Configuration.jsonDecoder.decode(
          StoredSession.self,
          from: data
        )
      {
        let session = try AuthClient.Configuration.jsonEncoder.encode(storedSession.session)
        try storage.store(key: key, value: session)
      }
    }
  }

  static func useDefaultEncoder(configuration: AuthClient.Configuration) -> StorageMigration {
    StorageMigration(name: "useDefaultEncoder") {
      let storage = configuration.localStorage
      let key = SessionStorage.key(configuration)

      let storedData = try? storage.retrieve(key: key)
      let sessionUsingOldDecoder = storedData.flatMap {
        try? AuthClient.Configuration.jsonDecoder.decode(Session.self, from: $0)
      }

      if let sessionUsingOldDecoder {
        try storage.store(
          key: key,
          value: JSONEncoder().encode(sessionUsingOldDecoder)
        )
      }
    }
  }
}
