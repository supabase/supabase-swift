//
//  Mocks.swift
//
//
//  Created by Guilherme Souza on 27/10/23.
//

import ConcurrencyExtras
import Foundation
import TestHelpers
import IssueReporting

@testable import Auth

let clientURL = URL(string: "http://localhost:54321/auth/v1")!

extension Dependencies {
  /// Signs `session` in through the session store, the only writer of the session.
  func seedSession(_ session: Session) async throws {
    try await sessionStore.commit(.signedIn(session, event: .signedIn))
  }
}

extension AuthClient {
  /// Signs `session` in through the session store, the only writer of the session.
  func seedSession(_ session: Session) async throws {
    try await dependencies.seedSession(session)
  }
}

/// A storage key no other test uses, so that clients built by parallel tests never share a
/// session store.
func uniqueStorageKey() -> String {
  "sb-test-\(UUID().uuidString)-auth-token"
}

// The server expiry is a fixed date, not the wall clock when a test first touches the fixture, so
// a long test run cannot age it. A store judges expiry from its receipt time plus `expiresIn`,
// and ignores a server expiry this far off.
extension Session {
  /// Valid for 120 seconds after a store receives it. Read from storage without a receipt time,
  /// it never expires.
  static let valid = Session(
    accessToken: "accesstoken",
    tokenType: "bearer",
    expiresIn: 120,
    expiresAt: 4_102_444_800,
    refreshToken: "refreshtoken",
    user: User(fromMockNamed: "user")
  )

  /// Inside the expiry margin as soon as a store receives it.
  static let expired = Session(
    accessToken: "accesstoken",
    tokenType: "bearer",
    expiresIn: defaultExpiryMargin.timeInterval / 3,
    expiresAt: 1_700_000_000,
    refreshToken: "refreshtoken",
    user: User(fromMockNamed: "user")
  )
}
