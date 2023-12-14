//
//  Mocks.swift
//
//
//  Created by Guilherme Souza on 27/10/23.
//

import ConcurrencyExtras
import Foundation
import XCTestDynamicOverlay
@_spi(Internal) import _Helpers

@testable import Auth

let clientURL = URL(string: "http://localhost:54321/auth/v1")!

extension CodeVerifierStorage {
  static let mock = Self(
    getCodeVerifier: unimplemented("CodeVerifierStorage.getCodeVerifier"),
    storeCodeVerifier: unimplemented("CodeVerifierStorage.storeCodeVerifier"),
    deleteCodeVerifier: unimplemented("CodeVerifierStorage.deleteCodeVerifier")
  )
}

extension SessionManager {
  static let mock = Self(
    session: unimplemented("SessionManager.session"),
    update: unimplemented("SessionManager.update"),
    remove: unimplemented("SessionManager.remove")
  )
}

extension EventEmitter {
  static let mock = Self(
    attachListener: unimplemented("EventEmitter.attachListener"),
    emit: unimplemented("EventEmitter.emit")
  )

  static let noop = Self(
    attachListener: { (UUID(), AsyncStream.makeStream().stream) },
    emit: { _, _, _ in }
  )
}

extension SessionStorage {
  static let mock = Self(
    getSession: unimplemented("SessionStorage.getSession"),
    storeSession: unimplemented("SessionStorage.storeSession"),
    deleteSession: unimplemented("SessionStorage.deleteSession")
  )

  static var inMemory: Self {
    let session = LockIsolated(StoredSession?.none)

    return Self(
      getSession: { session.value },
      storeSession: { session.setValue($0) },
      deleteSession: { session.setValue(nil) }
    )
  }
}

extension SessionRefresher {
  static let mock = Self(refreshSession: unimplemented("SessionRefresher.refreshSession"))
}

extension APIClient {
  static let mock = APIClient(execute: unimplemented("APIClient.execute"))
}

extension Dependencies {
  static let mock = Dependencies(
    configuration: AuthClient.Configuration(url: clientURL),
    sessionManager: .mock,
    api: .mock,
    eventEmitter: .mock,
    sessionStorage: .mock,
    sessionRefresher: .mock,
    codeVerifierStorage: .mock
  )
}

func withDependencies(
  _ mutation: (inout Dependencies) throws -> Void,
  operation: () async throws -> Void
) async rethrows {
  let current = Dependencies.current.value ?? .mock
  var copy = current
  try mutation(&copy)
  Dependencies.current.withValue { [copy] in $0 = copy }
  defer { Dependencies.current.setValue(current) }
  try await operation()
}

extension Session {
  static let validSession = Session(
    accessToken: "accesstoken",
    tokenType: "bearer",
    expiresIn: 120,
    expiresAt: Date().addingTimeInterval(120).timeIntervalSince1970,
    refreshToken: "refreshtoken",
    user: User(fromMockNamed: "user")
  )

  static let expiredSession = Session(
    accessToken: "accesstoken",
    tokenType: "bearer",
    expiresIn: 60,
    expiresAt: Date().addingTimeInterval(60).timeIntervalSince1970,
    refreshToken: "refreshtoken",
    user: User(fromMockNamed: "user")
  )
}

final class InMemoryLocalStorage: AuthLocalStorage, @unchecked Sendable {
  let storage = LockIsolated([String: Data]())

  func store(key: String, value: Data) throws {
    storage.withValue {
      $0[key] = value
    }
  }

  func retrieve(key: String) throws -> Data? {
    storage.value[key]
  }

  func remove(key: String) throws {
    storage.withValue {
      $0[key] = nil
    }
  }
}
