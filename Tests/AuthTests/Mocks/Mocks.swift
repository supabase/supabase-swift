//
//  Mocks.swift
//
//
//  Created by Guilherme Souza on 27/10/23.
//

import _Helpers
import ConcurrencyExtras
import Foundation
import TestHelpers
import XCTestDynamicOverlay

@testable import Auth

let clientURL = URL(string: "http://localhost:54321/auth/v1")!

extension CodeVerifierStorage {
  static let mock = Self(
    get: unimplemented("CodeVerifierStorage.get"),
    set: unimplemented("CodeVerifierStorage.set")
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

extension Dependencies {
  static let mock = Dependencies(
    configuration: AuthClient.Configuration(
      url: clientURL,
      localStorage: InMemoryLocalStorage(),
      logger: nil
    ),
    sessionManager: .mock,
    api: .mock,
    eventEmitter: .mock,
    sessionStorage: .mock,
    sessionRefresher: .mock,
    codeVerifierStorage: .mock,
    logger: nil
  )
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
