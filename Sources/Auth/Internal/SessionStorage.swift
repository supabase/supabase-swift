//
//  SessionStorage.swift
//
//
//  Created by Guilherme Souza on 24/10/23.
//

import _Helpers
import Foundation

/// A locally stored ``Session``, it contains metadata such as `expirationDate`.
struct StoredSession: Codable {
  var session: Session
  var expirationDate: Date
}

struct SessionStorage: Sendable {
  var getSession: @Sendable () throws -> Session?
  var storeSession: @Sendable (_ session: Session) throws -> Void
  var deleteSession: @Sendable () throws -> Void
}

extension SessionStorage {
  static let live: Self = {
    @Dependency(\.configuration.localStorage) var localStorage
    @Dependency(\.logger) var logger

    let encoder = AuthClient.Configuration.jsonEncoder
    let decoder = AuthClient.Configuration.jsonDecoder

    return Self(
      getSession: {
        logger?.debug("getSession begin")
        defer { logger?.debug("getSession end") }

        migrateFromStoredSessionToSessionIfNeeded(encoder: encoder, decoder: decoder)

        return try localStorage.retrieve(key: "supabase.session").flatMap {
          try decoder.decode(Session.self, from: $0)
        }
      },
      storeSession: {
        try localStorage.store(
          key: "supabase.session",
          value: encoder.encode($0)
        )
      },
      deleteSession: {
        try localStorage.remove(key: "supabase.session")
      }
    )
  }()

  static func migrateFromStoredSessionToSessionIfNeeded(encoder: JSONEncoder, decoder: JSONDecoder) {
    @Dependency(\.configuration.localStorage) var localStorage
    @Dependency(\.logger) var logger

    logger?.debug("start")
    defer { logger?.debug("end") }

    do {
      let storedData = try localStorage.retrieve(key: "supabase.session")

      let storedSession = storedData.flatMap {
        try? decoder.decode(StoredSession.self, from: $0)
      }?.session

      if let storedSession {
        logger?.debug("Migrate from StoredSession to Session")
        let session = try encoder.encode(storedSession)
        try localStorage.store(key: "supabase.session", value: session)
      }
    } catch {
      logger?.error("Error migrating stored session: \(error)")
    }
  }
}
