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
  func getSession() throws -> Session? {
    try retrieve(key: "supabase.session").flatMap {
      try AuthClient.Configuration.jsonDecoder.decode(StoredSession.self, from: $0).session
    }
  }

  func storeSession(_ session: Session) throws {
    try store(
      key: "supabase.session",
      value: AuthClient.Configuration.jsonEncoder.encode(StoredSession(session: session))
    )
  }

  func deleteSession() throws {
    try remove(key: "supabase.session")
  }
}
