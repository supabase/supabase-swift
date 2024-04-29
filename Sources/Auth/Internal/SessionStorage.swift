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

  var isValid: Bool {
    expirationDate.timeIntervalSince(Date()) > 60
  }

  init(session: Session, expirationDate: Date? = nil) {
    self.session = session
    self.expirationDate = expirationDate
      ?? session.expiresAt.map(Date.init(timeIntervalSince1970:))
      ?? Date().addingTimeInterval(session.expiresIn)
  }
}

extension AuthLocalStorage {
  func getSession() throws -> StoredSession? {
    try retrieve(key: "supabase.session").flatMap {
      try AuthClient.Configuration.jsonDecoder.decode(StoredSession.self, from: $0)
    }
  }

  func storeSession(_ session: StoredSession) throws {
    try store(
      key: "supabase.session",
      value: AuthClient.Configuration.jsonEncoder.encode(session)
    )
  }

  func deleteSession() throws {
    try remove(key: "supabase.session")
  }
}
