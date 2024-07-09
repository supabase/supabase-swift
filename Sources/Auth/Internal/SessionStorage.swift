//
//  SessionStorage.swift
//
//
//  Created by Guilherme Souza on 24/10/23.
//

import Foundation
import Helpers

/// A locally stored ``Session``, it contains metadata such as `expirationDate`.
struct StoredSession: Codable {
  var session: Session
  var expirationDate: Date

  init(session: Session, expirationDate _: Date? = nil) {
    self.session = session
    expirationDate = Date(timeIntervalSince1970: session.expiresAt)
  }
}

struct SessionStorage {
  var get: @Sendable () throws -> Session?
  var store: @Sendable (_ session: Session) throws -> Void
  var delete: @Sendable () throws -> Void
}

extension SessionStorage {
  static func live(clientID: AuthClientID) -> SessionStorage {
    var key: String {
      Dependencies[clientID].configuration.storageKey ?? AuthClient.Configuration.defaultStorageKey
    }

    var oldKey: String { "supabase.session" }

    var storage: any AuthLocalStorage {
      Dependencies[clientID].configuration.localStorage
    }

    return SessionStorage(
      get: {
        var storedData = try? storage.retrieve(key: oldKey)

        if let storedData {
          // migrate to new key.
          try storage.store(key: key, value: storedData)
          try? storage.remove(key: oldKey)
        } else {
          storedData = try storage.retrieve(key: key)
        }

        return try storedData.flatMap {
          try AuthClient.Configuration.jsonDecoder.decode(StoredSession.self, from: $0).session
        }
      },
      store: { session in
        try storage.store(
          key: key,
          value: AuthClient.Configuration.jsonEncoder.encode(StoredSession(session: session))
        )
      },
      delete: {
        try storage.remove(key: key)
        try? storage.remove(key: oldKey)
      }
    )
  }
}
