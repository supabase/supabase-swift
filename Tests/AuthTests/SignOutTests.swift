//
//  SignOutTests.swift
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

/// `signOut(scope:)` against the flowcharts of the Sign Out spec
/// (`packages/capability-matrix/specs/auth/session/sign_out.md` in `supabase/sdk`).
@Suite struct SignOutTests {
  let http = RecordingTransport()
  let sut: AuthClient

  init() {
    sut = .testing(http: http)
  }

  // MARK: - local

  @Test
  func defaultScopeIsLocal() async throws {
    http.respond { _, _ in noContent }
    try await sut.seedSession(.valid)

    try await sut.signOut()

    expectNoDifference(logoutRequests.map(\.scope), ["local"])
  }

  @Test
  func localRemovesTheSessionBeforeTheRequest() async throws {
    let heldDuringRequest = LockIsolated<Session?>(.valid)
    http.respond { [sut] _, _ in
      heldDuringRequest.setValue(sut.currentSession)
      return noContent
    }
    try await sut.seedSession(.valid)

    let (_, changes) = try await sut.recordingChanges { try await sut.signOut(scope: .local) }

    expectNoDifference(heldDuringRequest.value, nil)
    expectNoDifference(changes.map(\.event), [.initialSession, .signedOut])
    expectNoDifference(changes.last?.signOutReason, .userInitiated)
    expectNoDifference(logoutRequests.map(\.authorization), ["Bearer accesstoken"])
  }

  @Test
  func localClearsPendingPKCEFlows() async throws {
    http.respond { _, _ in noContent }
    let verifiers = sut.dependencies.codeVerifierStorage
    verifiers.set("verifier-1", "flow-1", .signIn)
    verifiers.set("verifier-2", "flow-2", .recovery)
    try await sut.seedSession(.valid)

    try await sut.signOut(scope: .local)

    expectNoDifference(verifiers.get("flow-1"), nil)
    expectNoDifference(verifiers.get("flow-2"), nil)
    expectNoDifference(verifiers.get(nil), nil)
  }

  @Test
  func localWithoutASessionEmitsTheSignOutAndSendsNothing() async throws {
    await sut.initialization()
    sut.dependencies.codeVerifierStorage.set("verifier", "flow", .signIn)

    let (_, changes) = try await sut.recordingChanges { try await sut.signOut(scope: .local) }

    expectNoDifference(changes.map(\.event), [.initialSession, .signedOut])
    expectNoDifference(sut.status, .signedOut(.userInitiated))
    expectNoDifference(sut.dependencies.codeVerifierStorage.get("flow"), nil)
    #expect(http.requests.isEmpty)
  }

  @Test(arguments: ["user_not_found", "session_not_found"])
  func localTreatsANothingLeftToRevokeAnswerAsSuccess(errorCode: String) async throws {
    http.respond { _, _ in errorResponse(.forbidden, errorCode) }
    try await sut.seedSession(.valid)

    try await sut.signOut(scope: .local)

    expectNoDifference(sut.status, .signedOut(.userInitiated))
  }

  @Test(arguments: [
    FailedAnswer(.unauthorized, "no_authorization"),
    FailedAnswer(.forbidden, "bad_jwt"),
    FailedAnswer(.forbidden, "user_banned"),
    FailedAnswer(.notFound, nil),
    FailedAnswer(.internalServerError, nil),
  ])
  func localThrowsAFailedLogoutAndStaysSignedOut(answer: FailedAnswer) async throws {
    http.respond { _, _ in errorResponse(answer.status, answer.errorCode) }
    try await sut.seedSession(.valid)

    let error = await #expect(throws: AuthError.self) { try await sut.signOut(scope: .local) }

    expectNoDifference(error?.response?.statusCode, answer.status.code)
    expectNoDifference(sut.status, .signedOut(.userInitiated))
  }

  @Test
  func localRefreshesAnExpiredTokenWithoutStoringIt() async throws {
    http.respond(when: isTokenRequest) { _, _ in try sessionResponse(.refreshed) }
    http.respond { _, _ in noContent }
    try await sut.seedSession(.expired)

    let (_, changes) = try await sut.recordingChanges { try await sut.signOut(scope: .local) }

    expectNoDifference(changes.map(\.event), [.initialSession, .signedOut])
    expectNoDifference(logoutRequests.map(\.authorization), ["Bearer refreshed-access-token"])
    expectNoDifference(sut.currentSession, nil)
    expectNoDifference(
      sut.dependencies.configuration.localStorage.hasValue(for: sut.storageKey), false)
  }

  @Test(arguments: ["refresh_token_not_found", "session_not_found", "session_expired"])
  func localTreatsAGoneSessionOnRefreshAsSuccess(errorCode: String) async throws {
    http.respond(when: isTokenRequest) { _, _ in errorResponse(.badRequest, errorCode) }
    try await sut.seedSession(.expired)

    try await sut.signOut(scope: .local)

    #expect(logoutRequests.isEmpty)
    expectNoDifference(sut.status, .signedOut(.userInitiated))
  }

  @Test(arguments: [
    FailedAnswer(.badRequest, "refresh_token_already_used"),
    FailedAnswer(.internalServerError, nil),
  ])
  func localThrowsAFailedRefreshAndStaysSignedOut(answer: FailedAnswer) async throws {
    http.respond(when: isTokenRequest) { _, _ in errorResponse(answer.status, answer.errorCode) }
    try await sut.seedSession(.expired)

    let error = await #expect(throws: AuthError.self) { try await sut.signOut(scope: .local) }

    expectNoDifference(error?.response?.statusCode, answer.status.code)
    #expect(logoutRequests.isEmpty)
    expectNoDifference(sut.status, .signedOut(.userInitiated))
  }

  @Test
  func localKeepsARefreshInFlightFromWritingTheSessionBack() async throws {
    let (release, releaseContinuation) = AsyncStream<Void>.makeStream()
    let refreshStarted = LockIsolated(false)
    http.respond(when: isTokenRequest) { _, _ in
      refreshStarted.setValue(true)
      _ = await release.first { _ in true }
      return try sessionResponse(.valid)
    }
    http.respond { _, _ in noContent }
    try await sut.seedSession(.valid)

    let refresh = Task { [sut] in try await sut.refreshSession() }
    try await withTimeout(.seconds(5)) {
      while !refreshStarted.value { await Task.yield() }
    }

    try await sut.signOut(scope: .local)
    releaseContinuation.yield()
    _ = await refresh.result

    expectNoDifference(sut.status, .signedOut(.userInitiated))
  }

  // MARK: - global

  @Test
  func globalRemovesTheSessionAfterTheServerEndsIt() async throws {
    let heldDuringRequest = LockIsolated<Session?>(nil)
    http.respond { [sut] _, _ in
      heldDuringRequest.setValue(sut.currentSession)
      return noContent
    }
    sut.dependencies.codeVerifierStorage.set("verifier", "flow", .signIn)
    try await sut.seedSession(.valid)

    let (_, changes) = try await sut.recordingChanges { try await sut.signOut(scope: .global) }

    expectNoDifference(heldDuringRequest.value, .valid)
    expectNoDifference(logoutRequests.map(\.scope), ["global"])
    expectNoDifference(changes.map(\.event), [.initialSession, .signedOut])
    expectNoDifference(sut.status, .signedOut(.userInitiated))
    expectNoDifference(sut.dependencies.codeVerifierStorage.get("flow"), nil)
  }

  @Test
  func globalTreatsAMissingUserAsSuccess() async throws {
    http.respond { _, _ in errorResponse(.forbidden, "user_not_found") }
    try await sut.seedSession(.valid)

    try await sut.signOut(scope: .global)

    expectNoDifference(sut.status, .signedOut(.userInitiated))
  }

  @Test(arguments: [
    FailedAnswer(.forbidden, "session_not_found"),
    FailedAnswer(.forbidden, "user_banned"),
    FailedAnswer(.unauthorized, "no_authorization"),
    FailedAnswer(.notFound, nil),
    FailedAnswer(.internalServerError, nil),
  ])
  func globalKeepsTheSessionWhenTheLogoutFails(answer: FailedAnswer) async throws {
    http.respond { _, _ in errorResponse(answer.status, answer.errorCode) }
    try await sut.seedSession(.valid)

    let (_, changes) = try await sut.recordingChanges {
      let error = await #expect(throws: AuthError.self) { try await sut.signOut(scope: .global) }
      expectNoDifference(error?.response?.statusCode, answer.status.code)
    }

    expectNoDifference(changes.map(\.event), [.initialSession])
    expectNoDifference(sut.currentSession, .valid)
  }

  @Test
  func globalRefreshesAndStoresAnExpiredToken() async throws {
    http.respond(when: isTokenRequest) { _, _ in try sessionResponse(.refreshed) }
    http.respond { _, _ in errorResponse(.internalServerError, nil) }
    try await sut.seedSession(.expired)

    await #expect(throws: AuthError.self) { try await sut.signOut(scope: .global) }

    expectNoDifference(logoutRequests.map(\.authorization), ["Bearer refreshed-access-token"])
    expectNoDifference(sut.currentSession?.refreshToken, "refreshed-refresh-token")
  }

  @Test(arguments: [
    FailedAnswer(.badRequest, "refresh_token_already_used"),
    FailedAnswer(.badRequest, "refresh_token_not_found"),
    FailedAnswer(.badRequest, "validation_failed"),
  ])
  func globalSignsOutAsUserInitiatedWhenTheRefreshIsRejected(answer: FailedAnswer) async throws {
    http.respond(when: isTokenRequest) { _, _ in errorResponse(answer.status, answer.errorCode) }
    try await sut.seedSession(.expired)

    let (_, changes) = try await sut.recordingChanges {
      let error = await #expect(throws: AuthError.self) { try await sut.signOut(scope: .global) }
      expectNoDifference(error?.errorCode.rawValue, answer.errorCode)
    }

    #expect(logoutRequests.isEmpty)
    expectNoDifference(changes.map(\.event), [.initialSession, .signedOut])
    expectNoDifference(sut.status, .signedOut(.userInitiated))
  }

  @Test
  func globalKeepsTheSessionWhenTheRefreshFailsOnTheServer() async throws {
    http.respond(when: isTokenRequest) { _, _ in errorResponse(.internalServerError, nil) }
    try await sut.seedSession(.expired)

    await #expect(throws: AuthError.self) { try await sut.signOut(scope: .global) }

    #expect(logoutRequests.isEmpty)
    expectNoDifference(sut.currentSession, .expired)
  }

  @Test
  func globalSignsOutARefreshThatLandsDuringTheRequest() async throws {
    http.respond { [sut] _, _ in
      try await sut.dependencies.sessionStore.commit(
        .refreshed(.refreshed, replacing: Session.valid.refreshToken))
      return noContent
    }
    try await sut.seedSession(.valid)

    try await sut.signOut(scope: .global)

    expectNoDifference(sut.status, .signedOut(.userInitiated))
  }

  @Test(arguments: ["validation_failed", "refresh_token_not_found"])
  func globalSignsOutAsUserInitiatedWhenARefreshItJoinsIsRejected(errorCode: String) async throws {
    let (release, releaseContinuation) = AsyncStream<Void>.makeStream()
    http.respond(when: isTokenRequest) { _, _ in
      _ = await release.first { _ in true }
      return errorResponse(.badRequest, errorCode)
    }
    try await sut.seedSession(.expired)
    let store = sut.dependencies.sessionStore

    let refresh = Task { [sut] in try await sut.refreshSession() }
    let signOut = Task { [sut] in try await sut.signOut(scope: .global) }
    try await withTimeout(.seconds(5)) {
      while await store.refreshCallerCount(for: Session.expired.refreshToken) < 2 {
        await Task.yield()
      }
    }
    releaseContinuation.yield()
    _ = await refresh.result

    await #expect(throws: AuthError.self) { try await signOut.value }
    #expect(logoutRequests.isEmpty)
    expectNoDifference(sut.status, .signedOut(.userInitiated))
  }

  @Test
  func globalSucceedsWhenASignOutLandsDuringTheRefresh() async throws {
    let (release, releaseContinuation) = AsyncStream<Void>.makeStream()
    let refreshStarted = LockIsolated(false)
    http.respond(when: isTokenRequest) { _, _ in
      refreshStarted.setValue(true)
      _ = await release.first { _ in true }
      return try sessionResponse(.refreshed)
    }
    try await sut.seedSession(.expired)

    let signOut = Task { [sut] in try await sut.signOut(scope: .global) }
    try await withTimeout(.seconds(5)) {
      while !refreshStarted.value { await Task.yield() }
    }
    try await sut.dependencies.sessionStore.commit(.signedOut(.sessionRevoked, event: .signedOut))
    releaseContinuation.yield()

    try await signOut.value
    #expect(logoutRequests.isEmpty)
    expectNoDifference(sut.status, .signedOut(.userInitiated))
  }

  @Test
  func globalWithoutASessionEmitsTheSignOutAndSendsNothing() async throws {
    await sut.initialization()

    let (_, changes) = try await sut.recordingChanges { try await sut.signOut(scope: .global) }

    expectNoDifference(changes.map(\.event), [.initialSession, .signedOut])
    expectNoDifference(sut.status, .signedOut(.userInitiated))
    #expect(http.requests.isEmpty)
  }

  // MARK: - others

  @Test
  func othersKeepsTheLocalSession() async throws {
    http.respond { _, _ in noContent }
    try await sut.seedSession(.valid)

    let (_, changes) = try await sut.recordingChanges { try await sut.signOut(scope: .others) }

    expectNoDifference(logoutRequests.map(\.scope), ["others"])
    expectNoDifference(changes.map(\.event), [.initialSession])
    expectNoDifference(sut.currentSession, .valid)
  }

  @Test
  func othersTreatsAMissingUserAsSuccess() async throws {
    http.respond { _, _ in errorResponse(.forbidden, "user_not_found") }
    try await sut.seedSession(.valid)

    try await sut.signOut(scope: .others)

    expectNoDifference(sut.currentSession, .valid)
  }

  @Test(arguments: [
    FailedAnswer(.forbidden, "session_not_found"),
    FailedAnswer(.forbidden, "user_banned"),
    FailedAnswer(.internalServerError, nil),
  ])
  func othersKeepsTheLocalSessionWhenTheLogoutFails(answer: FailedAnswer) async throws {
    http.respond { _, _ in errorResponse(answer.status, answer.errorCode) }
    try await sut.seedSession(.valid)

    await #expect(throws: AuthError.self) { try await sut.signOut(scope: .others) }

    expectNoDifference(sut.currentSession, .valid)
  }

  @Test
  func othersWithoutASessionThrowsSessionMissing() async throws {
    await sut.initialization()

    let error = await #expect(throws: AuthError.self) { try await sut.signOut(scope: .others) }

    expectNoDifference(error?.kind, .sessionMissing)
    #expect(http.requests.isEmpty)
  }

  @Test
  func othersSignsOutAsSessionExpiredWhenTheRefreshIsRejected() async throws {
    http.respond(when: isTokenRequest) { _, _ in
      errorResponse(.badRequest, "refresh_token_not_found")
    }
    try await sut.seedSession(.expired)

    let error = await #expect(throws: AuthError.self) { try await sut.signOut(scope: .others) }

    expectNoDifference(error?.kind, .sessionInvalidated)
    #expect(logoutRequests.isEmpty)
    expectNoDifference(sut.status, .signedOut(.sessionExpired))
  }

  @Test
  func othersRefreshesAnExpiredTokenWhenAutoRefreshIsDisabled() async throws {
    let sut = AuthClient.testing(http: http, autoRefresh: .disabled)
    http.respond(when: isTokenRequest) { _, _ in try sessionResponse(.refreshed) }
    http.respond { _, _ in noContent }
    try await sut.seedSession(.expired)

    try await sut.signOut(scope: .others)

    expectNoDifference(logoutRequests.map(\.authorization), ["Bearer refreshed-access-token"])
    expectNoDifference(sut.currentSession?.refreshToken, "refreshed-refresh-token")
  }

  // MARK: - Helpers

  struct FailedAnswer: Sendable, CustomTestStringConvertible {
    let status: HTTPResponse.Status
    let errorCode: String?

    init(_ status: HTTPResponse.Status, _ errorCode: String?) {
      self.status = status
      self.errorCode = errorCode
    }

    var testDescription: String {
      "\(status.code) \(errorCode ?? "")"
    }
  }

  private var logoutRequests: [(scope: String?, authorization: String?)] {
    http.requests
      .filter { $0.head.url?.path.hasSuffix("/logout") == true }
      .map { request in
        let query = request.head.url.flatMap {
          URLComponents(url: $0, resolvingAgainstBaseURL: false)
        }
        return (
          query?.queryItems?.first { $0.name == "scope" }?.value,
          request.head.headerFields[.authorization]
        )
      }
  }
}

extension Session {
  fileprivate static let refreshed: Session = {
    var session = Session.valid
    session.accessToken = "refreshed-access-token"
    session.refreshToken = "refreshed-refresh-token"
    return session
  }()
}

extension AuthLocalStorage {
  fileprivate func hasValue(for key: String) -> Bool {
    (try? retrieve(key: key)) != nil
  }
}

extension AuthClient {
  fileprivate var storageKey: String {
    configuration.storageKey ?? defaultStorageKey
  }
}
