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
    @Dependency(\.configuration.localStorage) var localStorage: any AuthLocalStorage
    @Dependency(\.logger) var logger

    return Self(
      getSession: {
        logger?.debug("getSession begin")
        defer { logger?.debug("getSession end") }

        let storedData = try localStorage.retrieve(key: "supabase.session")

        let storedSession = storedData.flatMap {
          try? AuthClient.Configuration.jsonDecoder.decode(StoredSession.self, from: $0)
        }?.session

        if let storedSession {
          logger?.debug("Migrate from StoredSession to Session")
          let session = try AuthClient.Configuration.jsonEncoder.encode(storedSession)
          try localStorage.store(key: "supabase.session", value: session)
          return storedSession
        }

        return try storedData.flatMap {
          try AuthClient.Configuration.jsonDecoder.decode(Session.self, from: $0)
        }
      },
      storeSession: {
        try localStorage.store(
          key: "supabase.session",
          value: AuthClient.Configuration.jsonEncoder.encode($0)
        )
      },
      deleteSession: {
        try localStorage.remove(key: "supabase.session")
      }
    )
  }()
}
