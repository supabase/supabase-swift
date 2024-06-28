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

extension AuthLocalStorage {
  var key: String {
    Current.configuration.storageKey ?? AuthClient.Configuration.defaultStorageKey
  }

  var oldKey: String { "supabase.session" }

  func getSession() throws -> Session? {
    var storedData = try? retrieve(key: oldKey)

    if let storedData {
      // migrate to new key.
      try store(key: key, value: storedData)
      try? remove(key: oldKey)
    } else {
      storedData = try retrieve(key: key)
    }

    return try storedData.flatMap {
      try AuthClient.Configuration.jsonDecoder.decode(StoredSession.self, from: $0).session
    }
  }

  func storeSession(_ session: Session) throws {
    try store(
      key: key,
      value: AuthClient.Configuration.jsonEncoder.encode(StoredSession(session: session))
    )
  }

  func deleteSession() throws {
    try remove(key: key)
    try? remove(key: oldKey)
  }
}
