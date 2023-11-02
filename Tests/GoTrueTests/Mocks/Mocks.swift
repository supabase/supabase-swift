//
//  Mocks.swift
//
//
//  Created by Guilherme Souza on 27/10/23.
//

import Foundation
import XCTestDynamicOverlay
@_spi(Internal) import _Helpers

@testable import GoTrue

let clientURL = URL(string: "http://localhost:54321/auth/v1")!

extension CodeVerifierStorage {
  static let mock = Self(
    getCodeVerifier: unimplemented("getCodeVerifier"),
    storeCodeVerifier: unimplemented("storeCodeVerifier"),
    deleteCodeVerifier: unimplemented("deleteCodeVerifier")
  )
}

extension SessionManager {
  static let mock = Self(
    session: unimplemented("session"),
    update: unimplemented("update"),
    remove: unimplemented("remove")
  )
}

extension EventEmitter {
  static let mock = Self(
    attachListener: unimplemented("attachListener"),
    emit: unimplemented("emit")
  )

  static let noop = Self(
    attachListener: { (UUID(), AsyncStream.makeStream().stream) },
    emit: { _, _, _ in }
  )
}

extension SessionStorage {
  static let mock = Self(
    getSession: unimplemented("getSession"),
    storeSession: unimplemented("storeSession"),
    deleteSession: unimplemented("deleteSession")
  )
}

extension SessionRefresher {
  static let mock = Self(refreshSession: unimplemented("refreshSession"))
}

extension Dependencies {
  static let mock = Dependencies(
    configuration: GoTrueClient.Configuration(url: clientURL),
    sessionManager: .mock,
    api: APIClient(http: HTTPClient(fetchHandler: unimplemented("HTTPClient.fetch"))),
    eventEmitter: .mock,
    sessionStorage: .mock,
    sessionRefresher: .mock,
    codeVerifierStorage: .mock
  )
}

func withDependencies(
  _ mutation: (inout Dependencies) -> Void,
  operation: () async throws -> Void
) async rethrows {
  let current = Dependencies.current.value ?? .mock
  var copy = current
  mutation(&copy)
  Dependencies.current.withValue { $0 = copy }
  defer { Dependencies.current.setValue(current) }
  try await operation()
}

extension Session {
  static let validSession = Session(
    accessToken: "accesstoken",
    tokenType: "bearer",
    expiresIn: 120,
    refreshToken: "refreshtoken",
    user: User(fromMockNamed: "user")
  )

  static let expiredSession = Session(
    accessToken: "accesstoken",
    tokenType: "bearer",
    expiresIn: 60,
    refreshToken: "refreshtoken",
    user: User(fromMockNamed: "user")
  )
}
