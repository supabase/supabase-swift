//
//  SessionStorage.swift
//
//
//  Created by Guilherme Souza on 24/10/23.
//

import Foundation

struct SessionStorage {
  var get: @Sendable () -> Session?
  var store: @Sendable (_ session: Session) -> Void
  var delete: @Sendable () -> Void
}

extension SessionStorage {
  /// Key used to store session on ``AuthLocalStorage``.
  ///
  /// It uses value from ``AuthClient/Configuration/storageKey`` or default to `supabase.auth.token` if not provided.
  static func key(_ clientID: AuthClientID) -> String {
    Dependencies[clientID].configuration.storageKey ?? defaultStorageKey
  }

  static func live(client: AuthClient) -> SessionStorage {
    var storage: any AuthLocalStorage {
      client.configuration.localStorage
    }

    var logger: SupabaseLogger? {
      client.configuration.logger
    }

    let migrations: [StorageMigration] = [
      .sessionNewKey(client: client),
      .storeSessionDirectly(client: client),
      .useDefaultEncoder(client: client),
    ]

    var key: String {
      SessionStorage.key(client.clientID)
    }

    return SessionStorage(
      get: {
        for migration in migrations {
          do {
            try migration.run()
          } catch {
            logger?.error(
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
          logger?.error("Failed to retrieve session: \(error.localizedDescription)")
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
  var name: String
  var run: @Sendable () throws -> Void
}

extension StorageMigration {
  /// Migrate stored session from `supabase.session` key to the custom provided storage key
  /// or the default `supabase.auth.token` key.
  static func sessionNewKey(client: AuthClient) -> StorageMigration {
    StorageMigration(name: "sessionNewKey") {
      let storage = client.configuration.localStorage
      let newKey = SessionStorage.key(client.clientID)

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
  static func storeSessionDirectly(client: AuthClient) -> StorageMigration {
    struct StoredSession: Codable {
      var session: Session
      var expirationDate: Date
    }

    return StorageMigration(name: "storeSessionDirectly") {
      let storage = client.configuration.localStorage
      let key = SessionStorage.key(client.clientID)

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

  static func useDefaultEncoder(client: AuthClient) -> StorageMigration {
    StorageMigration(name: "useDefaultEncoder") {
      let storage = client.configuration.localStorage
      let key = SessionStorage.key(client.clientID)

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
