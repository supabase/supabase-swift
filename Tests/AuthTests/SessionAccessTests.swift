//
//  SessionAccessTests.swift
//  Auth
//

import ConcurrencyExtras
import CustomDump
import Foundation
import HTTPTypes
import Helpers
import TestHelpers
import Testing

@testable import Auth

@Suite struct SessionAccessTests {
  let http = RecordingTransport()
  let sut: AuthClient

  init() {
    sut = .testing(http: http)
  }

  // MARK: - importSession

  @Test
  func importSessionWithAnUnexpiredTokenFetchesTheUserAndSignsInOnce() async throws {
    http.respond { _, _ in (HTTPResponse(status: .ok), MockData.user) }
    await sut.initialization()

    let (session, changes) = try await sut.recordingChanges {
      try await sut.importSession(
        accessToken: unexpiredAccessToken, refreshToken: "imported-refresh-token")
    }

    expectNoDifference(changes.map(\.event), [.initialSession, .signedIn])
    expectNoDifference(session.accessToken, unexpiredAccessToken)
    expectNoDifference(session.refreshToken, "imported-refresh-token")
    expectNoDifference(sut.currentSession, session)
    expectNoDifference(
      http.requests.map { $0.head.headerFields[.authorization] },
      ["Bearer \(unexpiredAccessToken)"])
  }

  @Test
  func importSessionWithAnExpiredTokenRefreshesAndSignsInOnce() async throws {
    http.respond { _, _ in (HTTPResponse(status: .ok), MockData.session) }
    await sut.initialization()

    let (session, changes) = try await sut.recordingChanges {
      try await sut.importSession(
        accessToken: expiredAccessToken, refreshToken: "imported-refresh-token")
    }

    expectNoDifference(changes.map(\.event), [.initialSession, .signedIn])
    expectNoDifference(sut.currentSession, session)
    let body = try #require(http.requests.first?.body)
    expectNoDifference(
      String(decoding: body, as: UTF8.self), #"{"refresh_token":"imported-refresh-token"}"#)
  }

  @Test
  func importSessionRejectsAMalformedToken() async throws {
    let error = await #expect(throws: AuthError.self) {
      try await sut.importSession(accessToken: "not-a-jwt", refreshToken: "refresh-token")
    }

    expectNoDifference(error?.kind, .jwtVerificationFailed)
    #expect(http.requests.isEmpty)
  }

  @Test
  func importSessionKeepsTheStoredSessionWhenTheServerRejectsTheImportedOne() async throws {
    http.respond { _, _ in errorResponse(.badRequest, "refresh_token_not_found") }
    try await sut.seedSession(.valid)

    let (_, changes) = try await sut.recordingChanges {
      await #expect(throws: AuthError.self) {
        try await sut.importSession(
          accessToken: expiredAccessToken, refreshToken: "imported-refresh-token")
      }
    }

    expectNoDifference(changes.map(\.event), [.initialSession])
    expectNoDifference(sut.currentSession, .valid)
  }

  // MARK: - refreshSession()

  @Test
  func refreshSessionReadsStorageThatWasLockedAtLaunch() async throws {
    let storage = LockedLocalStorage()
    let key = uniqueStorageKey()
    try storage.store(
      key: key,
      value: PersistedSessionCodec.encode(ReceivedSession(session: .valid, receivedAt: Date()))
    )
    storage.isLocked.setValue(true)
    http.respond { _, _ in try sessionResponse(.valid) }
    let sut = AuthClient(
      configuration: .init(
        url: clientURL, storageKey: key, localStorage: storage, http: .init(transport: http),
        autoRefresh: .manual),
      date: { Date() },
      pkce: .live,
      platform: .live
    )

    let error = await #expect(throws: AuthError.self) { try await sut.refreshSession() }
    expectNoDifference(error?.kind, .storageUnavailable)

    storage.isLocked.setValue(false)
    let session = try await sut.refreshSession()
    expectNoDifference(session.refreshToken, Session.valid.refreshToken)
  }

  @Test
  func refreshSessionRefreshesTheHeldSession() async throws {
    var refreshed = Session.valid
    refreshed.refreshToken = "refreshed-refresh-token"
    http.respond { [refreshed] _, _ in try sessionResponse(refreshed) }
    try await sut.seedSession(.valid)

    let session = try await sut.refreshSession()

    expectNoDifference(session.refreshToken, "refreshed-refresh-token")
    expectNoDifference(sut.currentSession?.refreshToken, "refreshed-refresh-token")
  }

  // MARK: - claims()

  @Test
  func claimsPropagatesAFailedRefresh() async throws {
    http.respond { _, _ in errorResponse(.internalServerError, nil) }
    try await sut.seedSession(.expired)

    let error = await #expect(throws: AuthError.self) { try await sut.claims() }

    expectNoDifference(error?.kind, .server)
    expectNoDifference(error?.response?.statusCode, 500)
  }
}
