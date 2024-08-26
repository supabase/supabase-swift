//
//  SessionStorage.swift
//
//
//  Created by Guilherme Souza on 24/10/23.
//

import Foundation
import Helpers

struct SessionStorage {
  var get: @Sendable () throws -> Session?
  var store: @Sendable (_ session: Session) throws -> Void
  var delete: @Sendable () throws -> Void
}

extension SessionStorage {
  /// Key used to store session on ``AuthLocalStorage``.
  ///
  /// It uses value from ``AuthClient/Configuration/storageKey`` or default to `supabase.auth.token` if not provided.
  static func key(_ clientID: AuthClientID) -> String {
    Dependencies[clientID].configuration.storageKey ?? STORAGE_KEY
  }

  static func live(clientID: AuthClientID) -> SessionStorage {
    var storage: any AuthLocalStorage {
      Dependencies[clientID].configuration.localStorage
    }

    var logger: (any SupabaseLogger)? {
      Dependencies[clientID].configuration.logger
    }

    let migrations: [StorageMigration] = [
      .sessionNewKey(clientID: clientID),
      .storeSessionDirectly(clientID: clientID),
    ]

    var key: String {
      SessionStorage.key(clientID)
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

        let storedData = try storage.retrieve(key: key)
        return try storedData.flatMap {
          try AuthClient.Configuration.jsonDecoder.decode(Session.self, from: $0)
        }
      },
      store: { session in
        try storage.store(
          key: key,
          value: AuthClient.Configuration.jsonEncoder.encode(session)
        )
      },
      delete: {
        try storage.remove(key: key)
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
  static func sessionNewKey(clientID: AuthClientID) -> StorageMigration {
    StorageMigration {
      let storage = Dependencies[clientID].configuration.localStorage
      let newKey = SessionStorage.key(clientID)

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
  static func storeSessionDirectly(clientID: AuthClientID) -> StorageMigration {
    struct StoredSession: Codable {
      var session: Session
      var expirationDate: Date
    }

    return StorageMigration {
      let storage = Dependencies[clientID].configuration.localStorage
      let key = SessionStorage.key(clientID)

      if let data = try? storage.retrieve(key: key),
         let storedSession = try? AuthClient.Configuration.jsonDecoder.decode(StoredSession.self, from: data)
      {
        let session = try AuthClient.Configuration.jsonEncoder.encode(storedSession.session)
        try storage.store(key: key, value: session)
      }
    }
  }
}
