//
//  File.swift
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

protocol SessionStorage {
  func getSession() throws -> StoredSession?
  func storeSession(_ session: StoredSession) throws
  func deleteSession()
}

struct DefaultSessionStorage: SessionStorage {
  let localStorage: GoTrueLocalStorage

  func getSession() throws -> StoredSession? {
    try localStorage.retrieve(key: "supabase.session").flatMap {
      try JSONDecoder.goTrue.decode(StoredSession.self, from: $0)
    }
  }

  func storeSession(_ session: StoredSession) throws {
    try localStorage.store(key: "supabase.session", value: JSONEncoder.goTrue.encode(session))
  }

  func deleteSession() {
    try? localStorage.remove(key: "supabase.session")
  }
}
