//
//  Mocks.swift
//
//
//  Created by Guilherme Souza on 27/10/23.
//

import ConcurrencyExtras
import Foundation
import HTTPTypes
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

extension Dependencies {
  /// Redeems `refreshToken` through the session store, as a refresh with a token from elsewhere.
  func redeem(_ refreshToken: String) async throws -> Session {
    try await sessionStore.refresh(refreshToken, using: refreshRequest)
  }
}

extension AuthClient {
  /// Signs `session` in through the session store, the only writer of the session.
  func seedSession(_ session: Session) async throws {
    try await dependencies.seedSession(session)
  }

  /// A client whose network `http` answers, with auto refresh off.
  static func testing(http: RecordingTransport) -> AuthClient {
    AuthClient(
      configuration: .init(
        url: clientURL,
        storageKey: uniqueStorageKey(),
        localStorage: InMemoryLocalStorage(),
        http: .init(transport: http),
        autoRefresh: .manual
      ),
      date: { Date() },
      pkce: .live,
      platform: .live
    )
  }

  /// Runs `action` and returns its result with every change the client emitted up to its return.
  func recordingChanges<T>(
    _ action: () async throws -> T
  ) async throws -> (T, [AuthChange]) {
    let changes = events()
    let result = try await action()
    dependencies.sessionStore.finishChanges()
    return (result, await changes.collect())
  }
}

/// A storage key no other test uses, so that clients built by parallel tests never read each
/// other's stored session.
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

/// A GoTrue error response in the 2024-01-01 shape, or an empty JSON body when `errorCode` is
/// `nil`.
func errorResponse(_ status: HTTPResponse.Status, _ errorCode: String?) -> (HTTPResponse, Data) {
  var fields = HTTPFields()
  fields[.contentType] = "application/json"
  let body = errorCode.map { #"{"code":"\#($0)","message":"\#($0)"}"# } ?? "{}"
  return (HTTPResponse(status: status, headerFields: fields), Data(body.utf8))
}

/// An empty `204 No Content` answer.
let noContent = (HTTPResponse(status: .noContent), Data())

/// A `200 OK` answer with `session` as the body.
func sessionResponse(_ session: Session) throws -> (HTTPResponse, Data) {
  (HTTPResponse(status: .ok), try AuthClient.Configuration.jsonEncoder.encode(session))
}

let isTokenRequest: @Sendable (HTTPRequest) -> Bool = {
  $0.url?.path.hasSuffix("/token") == true
}

/// A JWT whose `exp` is in 2123.
let unexpiredAccessToken =
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJhdWQiOiJhdXRoZW50aWNhdGVkIiwiZXhwIjo0ODUyMTYzNTkzLCJzdWIiOiJmMzNkM2VjOS1hMmVlLTQ3YzQtODBlMS01YmQ5MTlmM2Q4YjgiLCJlbWFpbCI6ImhpQGJpbmFyeXNjcmFwaW5nLmNvIiwicGhvbmUiOiIiLCJhcHBfbWV0YWRhdGEiOnsicHJvdmlkZXIiOiJlbWFpbCIsInByb3ZpZGVycyI6WyJlbWFpbCJdfSwidXNlcl9tZXRhZGF0YSI6e30sInJvbGUiOiJhdXRoZW50aWNhdGVkIn0.UiEhoahP9GNrBKw_OHBWyqYudtoIlZGkrjs7Qa8hU7I"

/// A JWT whose `exp` is in 2022.
let expiredAccessToken =
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJhdWQiOiJhdXRoZW50aWNhdGVkIiwiZXhwIjoxNjQ4NjQwMDIxLCJzdWIiOiJmMzNkM2VjOS1hMmVlLTQ3YzQtODBlMS01YmQ5MTlmM2Q4YjgiLCJlbWFpbCI6ImhpQGJpbmFyeXNjcmFwaW5nLmNvIiwicGhvbmUiOiIiLCJhcHBfbWV0YWRhdGEiOnsicHJvdmlkZXIiOiJlbWFpbCIsInByb3ZpZGVycyI6WyJlbWFpbCJdfSwidXNlcl9tZXRhZGF0YSI6e30sInJvbGUiOiJhdXRoZW50aWNhdGVkIn0.CGr5zNE5Yltlbn_3Ms2cjSLs_AW9RKM3lxh7cTQrg0w"
