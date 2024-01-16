//
//  SessionStorage.swift
//
//
//  Created by Guilherme Souza on 24/10/23.
//

import Foundation

/// A locally stored ``Session``, it contains metadata such as `expirationDate`.
struct StoredSession: Codable {
  var session: Session
  var expirationDate: Date

  var isValid: Bool {
    expirationDate > Date().addingTimeInterval(60)
  }

  init(session: Session, expirationDate: Date? = nil) {
    self.session = session
    self.expirationDate = expirationDate ?? Date().addingTimeInterval(session.expiresIn)
  }
}

struct SessionStorage: Sendable {
  var getSession: @Sendable () throws -> StoredSession?
  var storeSession: @Sendable (_ session: StoredSession) throws -> Void
  var deleteSession: @Sendable () throws -> Void
}

extension SessionStorage {
  static var live: Self = {
    var localStorage: AuthLocalStorage {
      Dependencies.current.withLock { $0!.configuration.localStorage }
    }

    return Self(
      getSession: {
        try localStorage.retrieve(key: "supabase.session").flatMap {
          try AuthClient.Configuration.jsonDecoder.decode(StoredSession.self, from: $0)
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
