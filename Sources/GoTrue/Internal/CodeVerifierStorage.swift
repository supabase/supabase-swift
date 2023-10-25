//
//  File.swift
//
//
//  Created by Guilherme Souza on 24/10/23.
//

import Foundation

protocol CodeVerifierStorage {
  func getCodeVerifier() throws -> String?
  func storeCodeVerifier(_ code: String) throws
  func deleteCodeVerifier() throws
}

struct DefaultCodeVerifierStorage: CodeVerifierStorage {
  let localStorage: GoTrueLocalStorage
  private let key = "supabase.code-verifier"

  func getCodeVerifier() throws -> String? {
    try localStorage.retrieve(key: key).flatMap {
      String(data: $0, encoding: .utf8)
    }
  }

  func storeCodeVerifier(_ code: String) throws {
    try localStorage.store(key: key, value: Data(code.utf8))
  }

  func deleteCodeVerifier() throws {
    try localStorage.remove(key: key)
  }
}
