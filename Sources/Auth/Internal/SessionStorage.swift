//
//  SessionStorage.swift
//
//
//  Created by Guilherme Souza on 24/10/23.
//

import Foundation
import Helpers

struct SessionStorage {
  var get: @Sendable () -> Session?
  var store: @Sendable (_ session: Session) -> Void
  var delete: @Sendable () -> Void
}

extension SessionStorage {
  /// Key used to store session on ``AuthLocalStorage``.
  ///
  /// It uses value from ``AuthClient/Configuration/storageKey`` or default to `supabase.auth.token` if not provided.
  static func key(_ configuration: AuthClient.Configuration) -> String {
    configuration.storageKey ?? defaultStorageKey
  }

  static func live(
    configuration: AuthClient.Configuration,
    logger: (any SupabaseLogger)?
  ) -> SessionStorage {
    var storage: any AuthLocalStorage {
      configuration.localStorage
    }

    let migrations: [StorageMigration] = [
      .sessionNewKey(configuration: configuration),
      .storeSessionDirectly(configuration: configuration),
    ]

    var key: String {
      SessionStorage.key(configuration)
    }

    return SessionStorage(
      get: {
        for migration in migrations {
          do {
            try migration.run()
          } catch {
            logger?.error("Storage migration failed: \(error.localizedDescription)")
          }
        }

        do {
          let storedData = try storage.retrieve(key: key)
          return try storedData.flatMap {
            try AuthClient.Configuration.jsonDecoder.decode(Session.self, from: $0)
          }
        } catch {
          logger?.error("Failed to retrieve session: \(error.localizedDescription)")
          return nil
        }
      },
      store: { session in
        do {
          try storage.store(
            key: key,
            value: AuthClient.Configuration.jsonEncoder.encode(session)
          )
        } catch {
          logger?.error("Failed to store session: \(error.localizedDescription)")
        }
      },
      delete: {
        do {
          try storage.remove(key: key)
        } catch {
          logger?.error("Failed to delete session: \(error.localizedDescription)")
        }
      }
    )
  }
}

struct StorageMigration {
  var run: @Sendable () throws -> Void
}

extension StorageMigration {
  /// Migrate stored session from `supabase.session` key to the custom provided storage key
  /// or the default `supabase.auth.token` key.
  static func sessionNewKey(configuration: AuthClient.Configuration) -> StorageMigration {
    StorageMigration {
      let storage = configuration.localStorage
      let newKey = SessionStorage.key(configuration)

      if let storedData = try? storage.retrieve(key: "supabase.session") {
        // migrate to new key.
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

    return StorageMigration {
      let storage = configuration.localStorage
      let key = SessionStorage.key(configuration)

      if let data = try? storage.retrieve(key: key),
         let storedSession = try? AuthClient.Configuration.jsonDecoder.decode(StoredSession.self, from: data)
      {
        let session = try AuthClient.Configuration.jsonEncoder.encode(storedSession.session)
        try storage.store(key: key, value: session)
      }
    }
  }
}
