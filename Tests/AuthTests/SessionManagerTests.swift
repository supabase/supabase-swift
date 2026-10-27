//
//  SessionManagerTests.swift
//
//
//  Created by Guilherme Souza on 23/10/23.
//

import ConcurrencyExtras
import CustomDump
import Foundation
import InlineSnapshotTesting
import Logging
import TestHelpers
import Testing

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@testable import Auth

@Suite(.serialized, .mainSerialExecutorSerialized)
struct SessionManagerTests {
  let http = RecordingTransport()
  let dependencies: Dependencies

  var sut: SessionManager {
    dependencies.sessionManager
  }

  init() {
    dependencies = Self.makeDependencies(http: http)
  }

  private static func makeDependencies(
    http: any ClientTransport,
    date: @escaping @Sendable () -> Date = { Date() }
  ) -> Dependencies {
    .live(
      configuration: .init(
        url: clientURL,
        storageKey: uniqueStorageKey(),
        localStorage: InMemoryLocalStorage(),
        autoRefresh: .manual
      ),
      http: HTTPClient(transport: http),
      logger: supabaseDefaultLogger(label: "io.supabase.auth"),
      date: date
    )
  }

  private var tokenRequestCount: Int {
    http.requests.filter { $0.head.url?.path.contains("/token") == true }.count
  }

  @Test
  func session_shouldFailWithSessionNotFound() async {
    await withMainSerialExecutor {
      do {
        _ = try await sut.session()
        Issue.record("Expected a \(AuthError.sessionMissing) failure")
      } catch {
        #expect((error as? AuthError)?.kind == .sessionMissing)
      }
    }
  }

  @Test
  func cancellationFromTransportIsNotWrapped() async throws {
    http.respond { _, _ in throw CancellationError() }
    try await dependencies.seedSession(.expired)

    await #expect(throws: CancellationError.self) {
      _ = try await sut.session()
    }
  }

  @Test
  func customFetchErrorIsNotWrapped() async throws {
    struct FetchError: Error {}
    http.respond { _, _ in throw FetchError() }
    try await dependencies.seedSession(.expired)

    await #expect(throws: FetchError.self) {
      _ = try await sut.session()
    }
  }

  @Test
  func session_shouldReturnValidSession() async throws {
    try await withMainSerialExecutor {
      let session = Session.valid
      try await dependencies.seedSession(session)

      let returnedSession = try await sut.session()
      expectNoDifference(returnedSession, session)
    }
  }

  @Test
  func session_shouldRefreshSession_whenCurrentSessionExpired() async throws {
    try await withMainSerialExecutor {
      let currentSession = Session.expired
      try await dependencies.seedSession(currentSession)

      let validSession = Session.valid

      let refreshSessionCallCount = LockIsolated(0)

      let (refreshSessionStream, refreshSessionContinuation) = AsyncStream<Session>.makeStream()

      http.respond(when: { $0.url?.path.contains("/token") == true }) { _, _ in
        refreshSessionCallCount.withValue { $0 += 1 }
        let session = await refreshSessionStream.first(where: { _ in true })!
        return (HTTPResponse(status: .ok), try AuthClient.Configuration.jsonEncoder.encode(session))
      }

      let tasks = (0..<10).map { _ in
        Task {
          try await sut.session()
        }
      }

      await Task.yield()

      refreshSessionContinuation.yield(validSession)
      refreshSessionContinuation.finish()

      var result: [Result<Session, any Error>] = []
      for task in tasks {
        let value = await task.result
        result.append(value)
      }

      expectNoDifference(refreshSessionCallCount.value, 1)
      expectNoDifference(
        try result.map { try $0.get().accessToken },
        (0..<10).map { _ in validSession.accessToken }
      )
    }
  }

  private func session(_ name: String) -> Session {
    Session(
      accessToken: "\(name)-access",
      tokenType: "bearer",
      expiresIn: 120,
      expiresAt: Date().addingTimeInterval(120).timeIntervalSince1970,
      refreshToken: "\(name)-refresh",
      user: User(fromMockNamed: "user")
    )
  }

  private func expiredSession(_ name: String) -> Session {
    var session = session(name)
    session.expiresIn = defaultExpiryMargin.timeInterval / 3
    session.expiresAt = Date().addingTimeInterval(session.expiresIn).timeIntervalSince1970
    return session
  }

  private func heldTokenResponse(
    _ response: @escaping @Sendable () throws -> (HTTPResponse, Data)
  ) -> (requestSeen: LockIsolated<Bool>, release: @Sendable () -> Void) {
    let (gate, continuation) = AsyncStream<Void>.makeStream()
    let requestSeen = LockIsolated(false)

    http.respond(when: { $0.url?.path.contains("/token") == true }) { _, _ in
      requestSeen.setValue(true)
      _ = await gate.first(where: { _ in true })
      return try response()
    }

    return (
      requestSeen,
      {
        continuation.yield(())
        continuation.finish()
      }
    )
  }

  private func collectAuthEvents(
    from store: SessionStore? = nil
  ) -> (events: LockIsolated<[AuthChangeEvent]>, stop: () -> Void) {
    let events = LockIsolated<[AuthChangeEvent]>([])
    let changes = (store ?? dependencies.sessionStore).changes()
    let task = Task {
      for await change in changes {
        events.withValue { $0.append(change.event) }
      }
    }
    return (events, { task.cancel() })
  }

  /// The events collected once `count` arrived, after giving any later event the chance to.
  private func settled(
    _ events: LockIsolated<[AuthChangeEvent]>, count: Int
  ) async -> [AuthChangeEvent] {
    await waitUntil { events.value.count >= count }
    await Task.megaYield()
    return events.value
  }

  @Test
  func refreshWithAGivenTokenRedeemsItWhileAnotherSessionIsHeld() async throws {
    let other = session("B")
    try await dependencies.seedSession(session("A"))
    http.respond(when: { $0.url?.path.contains("/token") == true }) { _, _ in
      (HTTPResponse(status: .ok), try AuthClient.Configuration.jsonEncoder.encode(other))
    }

    let refreshed = try await sut.refreshSession("foreign-refresh")

    expectNoDifference(refreshed.refreshToken, other.refreshToken)
    expectNoDifference(tokenRequestCount, 1)
  }

  @Test
  func staleRefreshDoesNotOverwriteANewerStoredSession() async throws {
    let userA = session("A")
    let userB = session("B")
    let refreshedA = session("A2")

    try await dependencies.seedSession(userA)
    let (requestSeen, release) = heldTokenResponse {
      (HTTPResponse(status: .ok), try AuthClient.Configuration.jsonEncoder.encode(refreshedA))
    }
    let (events, stopCollecting) = collectAuthEvents()
    defer { stopCollecting() }

    let refresh = Task { try await sut.refreshSession(userA.refreshToken) }
    let sawRequest = await waitUntil { requestSeen.value }
    #expect(sawRequest)

    try await dependencies.seedSession(userB)

    release()
    let result = await refresh.result

    expectNoDifference(
      dependencies.sessionStore.currentSession?.refreshToken, userB.refreshToken)
    let collected = await settled(events, count: 2)
    expectNoDifference(collected, [.initialSession, .signedIn])
    #expect((result.error as? AuthError)?.kind == .refreshDiscarded)
  }

  @Test
  func userUpdateDuringAnAutoRefreshKeepsTheRotatedTokensAndRedeemsTheTokenOnce() async throws {
    let held = expiredSession("A")
    let rotated = {
      var session = session("A2")
      session.expiresIn = 3600
      session.expiresAt = Date().addingTimeInterval(3600).timeIntervalSince1970
      return session
    }()

    try await dependencies.seedSession(held)
    let (requestSeen, release) = heldTokenResponse {
      (HTTPResponse(status: .ok), try AuthClient.Configuration.jsonEncoder.encode(rotated))
    }
    let (events, stopCollecting) = collectAuthEvents()
    defer { stopCollecting() }

    let owner = UUID()
    await dependencies.sessionStore.startAutoRefresh(
      for: owner,
      using: Refresher.Driver(
        clock: ContinuousClock(), logger: dependencies.logger,
        request: { [dependencies] refreshToken in
          try await dependencies.api.execute(
            dependencies.authAPI.refreshSession(refreshToken: refreshToken))
        }
      )
    )
    #expect(await waitUntil { requestSeen.value })

    var updatedUser = held.user
    updatedUser.email = "updated@example.com"
    try await dependencies.sessionStore.commit(.userUpdated(updatedUser, event: .userUpdated))
    release()

    let collected = await settled(events, count: 3)
    _ = await waitUntil(timeout: 3) { tokenRequestCount > 1 }
    await dependencies.sessionStore.stopAutoRefresh(for: owner)

    var expected = rotated
    expected.user = updatedUser
    expectNoDifference(dependencies.sessionStore.currentSession, expected)
    expectNoDifference(collected, [.initialSession, .userUpdated, .tokenRefreshed])
    expectNoDifference(tokenRequestCount, 1)
  }

  @Test
  func refreshIsDiscardedAfterASignOutAndASignInAsAnotherUser() async throws {
    let userA = session("A")
    let userB = session("B")

    try await dependencies.seedSession(userA)
    let (requestSeen, release) = heldTokenResponse {
      (HTTPResponse(status: .ok), try AuthClient.Configuration.jsonEncoder.encode(session("A2")))
    }

    let refresh = Task { try await sut.refreshSession(userA.refreshToken) }
    #expect(await waitUntil { requestSeen.value })

    try await dependencies.sessionStore.commit(.signedOut(.userInitiated, event: .signedOut))
    try await dependencies.seedSession(userB)
    release()
    let result = await refresh.result

    expectNoDifference(dependencies.sessionStore.currentSession, userB)
    #expect(result.error != nil)
  }

  @Test
  func staleRefreshDoesNotDeleteANewerStoredSessionOnACleanupError() async throws {
    let userA = session("A")
    let userB = session("B")

    try await dependencies.seedSession(userA)
    let (requestSeen, release) = heldTokenResponse {
      (
        HTTPResponse(status: .badRequest, headerFields: [.apiVersionHeaderName: "2024-01-01"]),
        Data(#"{"code":"refresh_token_not_found","message":"Refresh Token Not Found"}"#.utf8)
      )
    }
    let (events, stopCollecting) = collectAuthEvents()
    defer { stopCollecting() }

    let refresh = Task { try await sut.refreshSession(userA.refreshToken) }
    let sawRequest = await waitUntil { requestSeen.value }
    #expect(sawRequest)

    try await dependencies.seedSession(userB)

    release()
    let result = await refresh.result

    expectNoDifference(
      dependencies.sessionStore.currentSession?.refreshToken, userB.refreshToken)
    let collected = await settled(events, count: 2)
    expectNoDifference(collected, [.initialSession, .signedIn])
    #expect((result.error as? AuthError)?.kind == .sessionInvalidated)
  }

  @Test
  func refreshForADifferentTokenDoesNotJoinAnInFlightRefresh() async throws {
    let userA = session("A")
    let userB = session("B")
    let refreshedA = session("A2")
    let refreshedB = session("B2")

    try await dependencies.seedSession(userA)

    let tokensRequested = LockIsolated<[String]>([])
    let (gate, continuation) = AsyncStream<Void>.makeStream()

    struct RefreshBody: Decodable { let refreshToken: String }

    http.respond(when: { $0.url?.path.contains("/token") == true }) { _, body in
      let refreshToken = try AuthClient.Configuration.jsonDecoder.decode(
        RefreshBody.self, from: body ?? Data()
      ).refreshToken
      tokensRequested.withValue { $0.append(refreshToken) }

      if refreshToken == userA.refreshToken {
        _ = await gate.first(where: { _ in true })
      }
      return (
        HTTPResponse(status: .ok),
        try AuthClient.Configuration.jsonEncoder.encode(
          refreshToken == userA.refreshToken ? refreshedA : refreshedB
        )
      )
    }

    let refreshA = Task { try await sut.refreshSession(userA.refreshToken) }
    let sawRequest = await waitUntil { tokensRequested.value.contains(userA.refreshToken) }
    #expect(sawRequest)

    try await dependencies.seedSession(userB)
    let refreshB = Task { try await sut.refreshSession(userB.refreshToken) }
    _ = await waitUntil { tokensRequested.value.count == 2 }

    continuation.yield(())
    continuation.finish()
    _ = await refreshA.result
    let resultB = await refreshB.result

    expectNoDifference(try resultB.get().refreshToken, refreshedB.refreshToken)
    expectNoDifference(tokensRequested.value.sorted(), [userA, userB].map(\.refreshToken).sorted())
  }

  @Test
  func refreshForTheSameTokenJoinsTheInFlightRefreshAfterAnotherTokenIntervened() async throws {
    let userA = session("A")
    let userB = session("B")

    try await dependencies.seedSession(userA)

    let tokensRequested = LockIsolated<[String]>([])
    let (gate, continuation) = AsyncStream<Void>.makeStream()

    struct RefreshBody: Decodable { let refreshToken: String }

    http.respond(when: { $0.url?.path.contains("/token") == true }) { _, body in
      let refreshToken = try AuthClient.Configuration.jsonDecoder.decode(
        RefreshBody.self, from: body ?? Data()
      ).refreshToken
      tokensRequested.withValue { $0.append(refreshToken) }

      if refreshToken == userA.refreshToken {
        _ = await gate.first(where: { _ in true })
      }
      return (
        HTTPResponse(status: .ok), try AuthClient.Configuration.jsonEncoder.encode(userA)
      )
    }

    let firstA = Task { try await sut.refreshSession(userA.refreshToken) }
    let sawFirstA = await waitUntil { tokensRequested.value.contains(userA.refreshToken) }
    #expect(sawFirstA)

    let refreshB = Task { try await sut.refreshSession(userB.refreshToken) }
    _ = await waitUntil { tokensRequested.value.contains(userB.refreshToken) }
    let secondA = Task { try await sut.refreshSession(userA.refreshToken) }
    _ = await waitUntil(timeout: 0.5) { tokensRequested.value.count > 2 }

    continuation.yield(())
    continuation.finish()
    _ = await firstA.result
    _ = await refreshB.result
    _ = await secondA.result

    expectNoDifference(tokensRequested.value.filter { $0 == userA.refreshToken }.count, 1)
  }

  @Test
  func refreshCommitsWhenStorageStartsEmpty() async throws {
    let hydrated = session("hydrated")

    http.respond(when: { $0.url?.path.contains("/token") == true }) { _, _ in
      (HTTPResponse(status: .ok), try AuthClient.Configuration.jsonEncoder.encode(hydrated))
    }

    let result = try await sut.refreshSession("externally-sourced-refresh")

    expectNoDifference(result.refreshToken, hydrated.refreshToken)
    expectNoDifference(
      dependencies.sessionStore.currentSession?.refreshToken, hydrated.refreshToken)
  }

  @Test
  func refreshStartingFromEmptyStorageDoesNotOverwriteASessionStoredMeanwhile() async throws {
    let hydrated = session("hydrated")
    let userB = session("B")

    let (requestSeen, release) = heldTokenResponse {
      (HTTPResponse(status: .ok), try AuthClient.Configuration.jsonEncoder.encode(hydrated))
    }
    let (events, stopCollecting) = collectAuthEvents()
    defer { stopCollecting() }

    let refresh = Task { try await sut.refreshSession(hydrated.refreshToken) }
    let sawRequest = await waitUntil { requestSeen.value }
    #expect(sawRequest)

    try await dependencies.seedSession(userB)

    release()
    let result = await refresh.result

    expectNoDifference(dependencies.sessionStore.currentSession?.refreshToken, userB.refreshToken)
    let collected = await settled(events, count: 2)
    expectNoDifference(collected, [.initialSession, .signedIn])
    #expect((result.error as? AuthError)?.kind == .refreshDiscarded)
  }

  @Test
  func refreshStartingFromEmptyStorageDoesNotDeleteASessionStoredMeanwhileOnACleanupError()
    async throws
  {
    let userB = session("B")

    let (requestSeen, release) = heldTokenResponse {
      (
        HTTPResponse(status: .badRequest, headerFields: [.apiVersionHeaderName: "2024-01-01"]),
        Data(#"{"code":"refresh_token_not_found","message":"Refresh Token Not Found"}"#.utf8)
      )
    }
    let (events, stopCollecting) = collectAuthEvents()
    defer { stopCollecting() }

    let refresh = Task { try await sut.refreshSession("externally-sourced-refresh") }
    let sawRequest = await waitUntil { requestSeen.value }
    #expect(sawRequest)

    try await dependencies.seedSession(userB)

    release()
    let result = await refresh.result

    expectNoDifference(dependencies.sessionStore.currentSession?.refreshToken, userB.refreshToken)
    let collected = await settled(events, count: 2)
    expectNoDifference(collected, [.initialSession, .signedIn])
    #expect((result.error as? AuthError)?.kind == .sessionInvalidated)
  }

  @Test
  func foreignRefreshTokenFailureDoesNotSignOutTheStoredSession() async throws {
    let userB = session("B")
    try await dependencies.seedSession(userB)

    http.respond(when: { $0.url?.path.contains("/token") == true }) { _, _ in
      (
        HTTPResponse(status: .badRequest, headerFields: [.apiVersionHeaderName: "2024-01-01"]),
        Data(#"{"code":"refresh_token_not_found","message":"Refresh Token Not Found"}"#.utf8)
      )
    }
    let (events, stopCollecting) = collectAuthEvents()
    defer { stopCollecting() }

    let result = await Task { try await sut.refreshSession("foreign-refresh") }.result

    expectNoDifference(dependencies.sessionStore.currentSession?.refreshToken, userB.refreshToken)
    let collected = await settled(events, count: 1)
    expectNoDifference(collected, [.initialSession])
    #expect((result.error as? AuthError)?.kind == .sessionInvalidated)
  }

  @Test
  func foreignRefreshTokenSuccessReplacesTheStoredSession() async throws {
    let userB = session("B")
    let refreshedA = session("A2")
    try await dependencies.seedSession(userB)

    http.respond(when: { $0.url?.path.contains("/token") == true }) { _, _ in
      (HTTPResponse(status: .ok), try AuthClient.Configuration.jsonEncoder.encode(refreshedA))
    }

    let result = try await sut.refreshSession("A-refresh")

    expectNoDifference(result.refreshToken, refreshedA.refreshToken)
    expectNoDifference(
      dependencies.sessionStore.currentSession?.refreshToken, refreshedA.refreshToken)
  }

  private func resultIfFinished<Success: Sendable>(
    of task: Task<Success, any Error>, within timeout: TimeInterval = 10
  ) async -> Result<Success, any Error>? {
    let result = LockIsolated<Result<Success, any Error>?>(nil)
    Task {
      let value = await task.result
      result.setValue(value)
    }
    await waitUntil(timeout: timeout) { result.value != nil }
    return result.value
  }

  private func rateLimitedTokenResponse() {
    http.respond(when: { $0.url?.path.contains("/token") == true }) { _, _ in
      (
        HTTPResponse(status: .tooManyRequests, headerFields: [.apiVersionHeaderName: "2024-01-01"]),
        Data(#"{"code":"over_request_rate_limit","message":"Request rate limit reached"}"#.utf8)
      )
    }
  }

  @Test
  func cancelledWaiterThrowsCancellationErrorWhileTheOthersGetTheRefreshedSession() async throws {
    let refreshed = session("refreshed")
    try await dependencies.seedSession(.expired)
    let (requestSeen, release) = heldTokenResponse {
      (HTTPResponse(status: .ok), try AuthClient.Configuration.jsonEncoder.encode(refreshed))
    }

    let waiters = (0..<3).map { _ in Task { try await sut.session() } }
    let sawRequest = await waitUntil { requestSeen.value }
    #expect(sawRequest)

    waiters[0].cancel()
    let cancelled = await resultIfFinished(of: waiters[0])
    #expect(cancelled?.error is CancellationError)

    release()
    for waiter in waiters.dropFirst() {
      let session = try await waiter.value
      expectNoDifference(session.refreshToken, refreshed.refreshToken)
    }
    expectNoDifference(
      dependencies.sessionStore.currentSession?.refreshToken, refreshed.refreshToken)
    expectNoDifference(tokenRequestCount, 1)
  }

  @Test
  func refreshCommitsAfterItsOnlyWaiterIsCancelled() async throws {
    let userA = session("A")
    let refreshed = session("A2")
    try await dependencies.seedSession(userA)
    let (requestSeen, release) = heldTokenResponse {
      (HTTPResponse(status: .ok), try AuthClient.Configuration.jsonEncoder.encode(refreshed))
    }

    let waiter = Task { try await sut.refreshSession(userA.refreshToken) }
    let sawRequest = await waitUntil { requestSeen.value }
    #expect(sawRequest)

    waiter.cancel()
    let cancelled = await resultIfFinished(of: waiter)
    #expect(cancelled?.error is CancellationError)

    release()
    let committed = await waitUntil {
      dependencies.sessionStore.currentSession?.refreshToken == refreshed.refreshToken
    }
    #expect(committed)
  }

  @Test
  func signOutCancelsTheInFlightRefresh() async throws {
    let userA = session("A")
    let refreshed = session("A2")
    try await dependencies.seedSession(userA)
    let (requestSeen, release) = heldTokenResponse {
      (HTTPResponse(status: .ok), try AuthClient.Configuration.jsonEncoder.encode(refreshed))
    }
    let (events, stopCollecting) = collectAuthEvents()
    defer { stopCollecting() }

    let refresh = Task { try await sut.refreshSession(userA.refreshToken) }
    let sawRequest = await waitUntil { requestSeen.value }
    #expect(sawRequest)

    try await dependencies.sessionStore.commit(.signedOut(.userInitiated, event: .signedOut))
    let outcome = await resultIfFinished(of: refresh)
    release()

    #expect(outcome?.error is CancellationError)
    #expect(dependencies.sessionStore.currentSession == nil)
    let collected = await settled(events, count: 2)
    expectNoDifference(collected, [.initialSession, .signedOut])
  }

  @Test
  func refreshOfATokenThatFailedLessThanAMinuteAgoThrowsTheSameErrorWithoutARequest()
    async throws
  {
    let now = LockIsolated(Date())
    let dependencies = Self.makeDependencies(http: http, date: { now.value })
    let sut = dependencies.sessionManager
    rateLimitedTokenResponse()

    let first = await Task { try await sut.refreshSession("limited") }.result
    now.withValue { $0.addTimeInterval(59) }
    let second = await Task { try await sut.refreshSession("limited") }.result

    #expect((first.error as? AuthError)?.errorCode == .overRequestRateLimit)
    #expect((second.error as? AuthError)?.errorCode == .overRequestRateLimit)
    expectNoDifference(tokenRequestCount, 1)

    now.withValue { $0.addTimeInterval(1) }
    _ = await Task { try await sut.refreshSession("limited") }.result
    expectNoDifference(tokenRequestCount, 2)
  }

  @Test
  func refreshOfAnInvalidatedTokenThrowsTheSameErrorWithoutARequest() async throws {
    let userA = expiredSession("A")
    try await dependencies.seedSession(userA)
    http.respond(when: { $0.url?.path.contains("/token") == true }) { _, _ in
      (
        HTTPResponse(status: .badRequest, headerFields: [.apiVersionHeaderName: "2024-01-01"]),
        Data(#"{"code":"refresh_token_not_found","message":"Refresh Token Not Found"}"#.utf8)
      )
    }

    let first = await Task { try await sut.refreshSession(userA.refreshToken) }.result
    let second = await Task { try await sut.refreshSession(userA.refreshToken) }.result

    #expect(dependencies.sessionStore.currentSession == nil)
    #expect((first.error as? AuthError)?.kind == .sessionInvalidated)
    #expect((second.error as? AuthError)?.kind == .sessionInvalidated)
    expectNoDifference(tokenRequestCount, 1)
  }

  @Test
  func commitClearsTheCachedRefreshFailure() async throws {
    rateLimitedTokenResponse()

    _ = await Task { try await sut.refreshSession("limited") }.result
    try await dependencies.seedSession(session("B"))
    _ = await Task { try await sut.refreshSession("limited") }.result

    expectNoDifference(tokenRequestCount, 2)
  }

  @Test
  func cachedRefreshFailureDoesNotBlockAnotherToken() async throws {
    rateLimitedTokenResponse()

    _ = await Task { try await sut.refreshSession("first") }.result
    _ = await Task { try await sut.refreshSession("second") }.result

    expectNoDifference(tokenRequestCount, 2)
  }

  @Test
  func sixthRefreshWithinThirtySecondsThrowsExcessiveRefresh() async throws {
    let now = LockIsolated(Date())
    let dependencies = Self.makeDependencies(http: http, date: { now.value })
    let sut = dependencies.sessionManager
    http.respond(when: { $0.url?.path.contains("/token") == true }) { _, _ in
      (HTTPResponse(status: .ok), try AuthClient.Configuration.jsonEncoder.encode(Session.valid))
    }

    for attempt in 0..<5 {
      _ = try await sut.refreshSession("token-\(attempt)")
    }
    now.withValue { $0.addTimeInterval(29) }
    let sixth = await Task { try await sut.refreshSession("token-5") }.result

    #expect((sixth.error as? AuthError)?.kind == .excessiveRefresh)
    expectNoDifference(tokenRequestCount, 5)

    now.withValue { $0.addTimeInterval(1) }
    _ = try await sut.refreshSession("token-6")
    expectNoDifference(tokenRequestCount, 6)
  }

  @Test
  func olderRefreshEndingDoesNotEndANewerRefreshOfTheSameToken() async throws {
    let userA = session("A")
    let refreshed = session("A2")
    try await dependencies.seedSession(userA)

    let requests = LockIsolated(0)
    let gates = LockIsolated<[CheckedContinuation<Void, Never>]>([])
    http.respond(when: { $0.url?.path.contains("/token") == true }) { _, _ in
      let request = requests.withValue {
        $0 += 1
        return $0
      }
      if request <= 2 {
        await withCheckedContinuation { gate in gates.withValue { $0.append(gate) } }
      }
      return (HTTPResponse(status: .ok), try AuthClient.Configuration.jsonEncoder.encode(refreshed))
    }

    let older = Task { try await sut.refreshSession(userA.refreshToken) }
    await waitUntil { gates.value.count == 1 }
    try await dependencies.sessionStore.commit(.signedOut(.userInitiated, event: .signedOut))

    let newer = Task { try await sut.refreshSession(userA.refreshToken) }
    let newerStarted = await waitUntil { gates.value.count == 2 }
    #expect(newerStarted)

    gates.value[0].resume()
    let olderResult = await older.result
    #expect(olderResult.error is CancellationError)

    let joiner = Task { try await sut.refreshSession(userA.refreshToken) }
    let joinerStartedARequest = await waitUntil(timeout: 0.5) { requests.value > 2 }
    gates.value[1].resume()

    let newerResult = await newer.result
    let joinerResult = await joiner.result

    #expect(!joinerStartedARequest)
    expectNoDifference(try newerResult.get().refreshToken, refreshed.refreshToken)
    expectNoDifference(try joinerResult.get().refreshToken, refreshed.refreshToken)
  }

  @Test
  func cachedRefreshFailureEndsWhenTheClockMovesBackward() async throws {
    let now = LockIsolated(Date())
    let dependencies = Self.makeDependencies(http: http, date: { now.value })
    let sut = dependencies.sessionManager
    rateLimitedTokenResponse()

    _ = await Task { try await sut.refreshSession("limited") }.result
    now.withValue { $0.addTimeInterval(-3600) }
    _ = await Task { try await sut.refreshSession("limited") }.result
    expectNoDifference(tokenRequestCount, 2)

    now.withValue { $0.addTimeInterval(120) }
    _ = await Task { try await sut.refreshSession("limited") }.result
    expectNoDifference(tokenRequestCount, 3)
  }

  @Test
  func refreshWindowForgetsRefreshesWhenTheClockMovesBackward() async throws {
    let now = LockIsolated(Date())
    let dependencies = Self.makeDependencies(http: http, date: { now.value })
    let sut = dependencies.sessionManager
    http.respond(when: { $0.url?.path.contains("/token") == true }) { _, _ in
      (HTTPResponse(status: .ok), try AuthClient.Configuration.jsonEncoder.encode(Session.valid))
    }

    for attempt in 0..<5 {
      _ = try await sut.refreshSession("token-\(attempt)")
    }
    now.withValue { $0.addTimeInterval(-3600) }
    _ = try await sut.refreshSession("token-5")

    expectNoDifference(tokenRequestCount, 6)
  }

  @Test
  func refreshCancelledBySignOutWhileReadingTheBodyThrowsCancellationErrorAndCachesNothing()
    async throws
  {
    let transport = URLErrorOnCancelTransport()
    let dependencies = Self.makeDependencies(http: transport)
    let sut = dependencies.sessionManager
    let userA = session("A")
    try await dependencies.seedSession(userA)

    let refresh = Task { try await sut.refreshSession(userA.refreshToken) }
    let readingBody = await waitUntil { transport.bodyReads.value == 1 }
    #expect(readingBody)

    try await dependencies.sessionStore.commit(.signedOut(.userInitiated, event: .signedOut))
    let outcome = await resultIfFinished(of: refresh)
    #expect(outcome?.error is CancellationError)

    _ = await Task { try await sut.refreshSession(userA.refreshToken) }.result
    expectNoDifference(transport.requests.value, 2)
  }

  @Test(arguments: RefreshFailure.all)
  func refreshFailureOfAnExpiredSession(_ failure: RefreshFailure) async throws {
    let held = expiredSession("A")
    try await dependencies.seedSession(held)
    http.respond(when: { $0.url?.path.contains("/token") == true }) { _, _ in
      try failure.response()
    }
    let (events, stopCollecting) = collectAuthEvents()
    defer { stopCollecting() }

    let result = await Task { try await sut.refreshSession(held.refreshToken) }.result

    let error = try #require(result.error as? AuthError)
    #expect(error.kind == failure.kind)
    #expect(error.isRetryable == failure.isRetryable)
    let (expectedStatus, expectedEvents): (AuthStatus, [AuthChangeEvent]) =
      switch failure.outcome {
      case .keepsSession: (.signedIn(held), [.initialSession])
      case .signsOut(let reason): (.signedOut(reason), [.initialSession, .signedOut])
      }
    let collected = await settled(events, count: expectedEvents.count)
    #expect(dependencies.sessionStore.currentStatus == expectedStatus)
    expectNoDifference(collected, expectedEvents)
  }

  @Test(arguments: RefreshFailure.all.filter { $0.outcome != .keepsSession })
  func rejectedRefreshKeepsASessionWhoseAccessTokenIsStillValid(_ failure: RefreshFailure)
    async throws
  {
    let held = session("A")
    try await dependencies.seedSession(held)
    http.respond(when: { $0.url?.path.contains("/token") == true }) { _, _ in
      try failure.response()
    }
    let (events, stopCollecting) = collectAuthEvents()
    defer { stopCollecting() }

    let result = await Task { try await sut.refreshSession(held.refreshToken) }.result

    let collected = await settled(events, count: 1)
    #expect((result.error as? AuthError)?.kind == .sessionInvalidated)
    #expect(dependencies.sessionStore.currentStatus == .signedIn(held))
    expectNoDifference(collected, [.initialSession])
  }

  @Test
  func accessTokenValidityIsJudgedByTheInjectedDate() async throws {
    let held = session("A")
    let now = LockIsolated(Date())
    let dependencies = Self.makeDependencies(http: http, date: { now.value })
    try await dependencies.seedSession(held)
    now.withValue { $0.addTimeInterval(held.expiresIn) }
    http.respond(when: { $0.url?.path.contains("/token") == true }) { _, _ in
      try RefreshFailure.coded("refresh_token_already_used", status: .badRequest).response()
    }

    _ = await Task { try await dependencies.sessionManager.refreshSession(held.refreshToken) }
      .result

    #expect(dependencies.sessionStore.currentStatus == .signedOut(.sessionRevoked))
  }

  @Test
  func cachedRejectionSignsOutOnceTheKeptSessionExpires() async throws {
    let now = LockIsolated(Date())
    let held = {
      var session = session("A")
      session.expiresIn = 60
      session.expiresAt = now.value.addingTimeInterval(60).timeIntervalSince1970
      return session
    }()
    let dependencies = Self.makeDependencies(http: http, date: { now.value })
    let sut = dependencies.sessionManager
    try await dependencies.seedSession(held)
    http.respond(when: { $0.url?.path.contains("/token") == true }) { _, _ in
      try RefreshFailure.coded("refresh_token_already_used", status: .badRequest).response()
    }

    _ = await Task { try await sut.refreshSession(held.refreshToken) }.result
    #expect(dependencies.sessionStore.currentStatus == .signedIn(held))

    now.withValue { $0.addTimeInterval(40) }
    let cached = await Task { try await sut.refreshSession(held.refreshToken) }.result

    #expect((cached.error as? AuthError)?.errorCode == .refreshTokenAlreadyUsed)
    #expect(dependencies.sessionStore.currentStatus == .signedOut(.sessionRevoked))
    expectNoDifference(tokenRequestCount, 1)
  }

  @Test
  func offlineRefreshOfAnExpiredSessionKeepsTheUserSignedIn() async throws {
    let held = expiredSession("A")
    try await dependencies.seedSession(held)
    http.respond(when: { $0.url?.path.contains("/token") == true }) { _, _ in
      throw URLError(.notConnectedToInternet)
    }
    let (events, stopCollecting) = collectAuthEvents()
    defer { stopCollecting() }

    let result = await Task { try await sut.session() }.result

    let collected = await settled(events, count: 1)
    #expect((result.error as? AuthError)?.kind == .transport)
    #expect(dependencies.sessionStore.currentStatus == .signedIn(held))
    expectNoDifference(collected, [.initialSession])
  }

  @Test
  func refreshAfterACachedRejectionSignedOutSendsNoRequest() async throws {
    let now = LockIsolated(Date())
    let held = {
      var session = session("A")
      session.expiresIn = 60
      session.expiresAt = now.value.addingTimeInterval(60).timeIntervalSince1970
      return session
    }()
    let dependencies = Self.makeDependencies(http: http, date: { now.value })
    let sut = dependencies.sessionManager
    try await dependencies.seedSession(held)
    http.respond(when: { $0.url?.path.contains("/token") == true }) { _, _ in
      try RefreshFailure.coded("refresh_token_already_used", status: .badRequest).response()
    }
    let (events, stopCollecting) = collectAuthEvents(from: dependencies.sessionStore)
    defer { stopCollecting() }

    _ = await Task { try await sut.refreshSession(held.refreshToken) }.result
    now.withValue { $0.addTimeInterval(40) }
    _ = await Task { try await sut.refreshSession(held.refreshToken) }.result

    let afterSignOut = await Task { try await sut.refreshSession(held.refreshToken) }.result
    #expect((afterSignOut.error as? AuthError)?.errorCode == .refreshTokenAlreadyUsed)

    let collected = await settled(events, count: 2)
    expectNoDifference(tokenRequestCount, 1)
    expectNoDifference(collected, [.initialSession, .signedOut])
    #expect(dependencies.sessionStore.currentStatus == .signedOut(.sessionRevoked))
  }

  @Test
  func concurrentCachedRejectionsSignOutOnce() async throws {
    let now = LockIsolated(Date())
    let held = {
      var session = session("A")
      session.expiresIn = 60
      session.expiresAt = now.value.addingTimeInterval(60).timeIntervalSince1970
      return session
    }()
    let dependencies = Self.makeDependencies(http: http, date: { now.value })
    let sut = dependencies.sessionManager
    try await dependencies.seedSession(held)
    http.respond(when: { $0.url?.path.contains("/token") == true }) { _, _ in
      try RefreshFailure.coded("refresh_token_already_used", status: .badRequest).response()
    }
    let (events, stopCollecting) = collectAuthEvents(from: dependencies.sessionStore)
    defer { stopCollecting() }

    _ = await Task { try await sut.refreshSession(held.refreshToken) }.result
    now.withValue { $0.addTimeInterval(40) }
    let refreshes = (0..<20).map { _ in
      Task { try await sut.refreshSession(held.refreshToken) }
    }
    for refresh in refreshes {
      _ = await refresh.result
    }

    let collected = await settled(events, count: 2)
    expectNoDifference(tokenRequestCount, 1)
    expectNoDifference(collected, [.initialSession, .signedOut])
  }

  @Test
  func rejectedRefreshWithoutASessionKeepsTheSignOutReason() async throws {
    http.respond(when: { $0.url?.path.contains("/token") == true }) { _, _ in
      try RefreshFailure.coded("refresh_token_not_found", status: .badRequest).response()
    }
    let (events, stopCollecting) = collectAuthEvents()
    defer { stopCollecting() }

    let result = await Task { try await sut.refreshSession("foreign") }.result

    let collected = await settled(events, count: 1)
    #expect((result.error as? AuthError)?.kind == .sessionInvalidated)
    #expect(dependencies.sessionStore.currentStatus == .signedOut(.sessionMissing))
    expectNoDifference(collected, [.initialSession])
  }

  @Test
  func cachedRejectionOfAnotherTokenKeepsTheHeldSession() async throws {
    let held = expiredSession("A")
    try await dependencies.seedSession(held)
    http.respond(when: { $0.url?.path.contains("/token") == true }) { _, _ in
      try RefreshFailure.coded("refresh_token_already_used", status: .badRequest).response()
    }
    let (events, stopCollecting) = collectAuthEvents()
    defer { stopCollecting() }

    _ = await Task { try await sut.refreshSession("foreign") }.result
    let cached = await Task { try await sut.refreshSession("foreign") }.result

    let collected = await settled(events, count: 1)
    #expect((cached.error as? AuthError)?.errorCode == .refreshTokenAlreadyUsed)
    #expect(dependencies.sessionStore.currentStatus == .signedIn(held))
    expectNoDifference(tokenRequestCount, 1)
    expectNoDifference(collected, [.initialSession])
  }
}

struct RefreshFailure: Sendable, CustomTestStringConvertible {
  var testDescription: String
  var response: @Sendable () throws -> (HTTPResponse, Data)
  var kind: AuthError.Kind
  var isRetryable: Bool
  var outcome = Outcome.keepsSession

  enum Outcome: Equatable {
    case keepsSession
    case signsOut(SignOutReason)
  }

  static func coded(
    _ code: String,
    status: HTTPResponse.Status,
    kind: AuthError.Kind = .sessionInvalidated,
    isRetryable: Bool = false,
    outcome: Outcome = .keepsSession
  ) -> Self {
    Self(
      testDescription: code,
      response: {
        (
          HTTPResponse(status: status, headerFields: [.apiVersionHeaderName: "2024-01-01"]),
          Data(#"{"code":"\#(code)","message":"m"}"#.utf8)
        )
      },
      kind: kind,
      isRetryable: isRetryable,
      outcome: outcome
    )
  }

  static func status(_ status: HTTPResponse.Status) -> Self {
    Self(
      testDescription: "HTTP \(status.code)",
      response: { (HTTPResponse(status: status), Data("<html></html>".utf8)) },
      kind: .server,
      isRetryable: true
    )
  }

  static let all: [Self] = [
    .coded("refresh_token_not_found", status: .badRequest, outcome: .signsOut(.sessionExpired)),
    .coded("session_expired", status: .badRequest, outcome: .signsOut(.sessionExpired)),
    .coded("refresh_token_already_used", status: .badRequest, outcome: .signsOut(.sessionRevoked)),
    .coded("session_not_found", status: .forbidden, outcome: .signsOut(.sessionRevoked)),
    .coded("user_banned", status: .forbidden, outcome: .signsOut(.sessionRevoked)),
    Self(
      testDescription: "invalid_grant",
      response: {
        (
          HTTPResponse(status: .badRequest),
          Data(#"{"error":"invalid_grant","error_description":"m"}"#.utf8)
        )
      },
      kind: .sessionInvalidated,
      isRetryable: false,
      outcome: .signsOut(.sessionExpired)
    ),
    .coded("conflict", status: .conflict, kind: .server, isRetryable: true),
    .coded("over_request_rate_limit", status: .tooManyRequests, kind: .server, isRetryable: true),
    .status(.requestTimeout),
    .status(.internalServerError),
    .status(.badGateway),
    .status(HTTPResponse.Status(code: 520)),
    Self(
      testDescription: "transport",
      response: { throw URLError(.notConnectedToInternet) },
      kind: .transport,
      isRetryable: true
    ),
    .coded("validation_failed", status: .badRequest, kind: .server),
  ]
}

/// Answers the first request with a body that throws `URLError(.cancelled)` once its reader is
/// cancelled, as a body from `URLSession.bytes(for:)` does, and fails every later request.
private struct URLErrorOnCancelTransport: ClientTransport {
  let requests = LockIsolated(0)
  let bodyReads = LockIsolated(0)

  func send(_ request: HTTPRequest, body: HTTPBody?) async throws -> (HTTPResponse, HTTPBody?) {
    let request = requests.withValue {
      $0 += 1
      return $0
    }
    guard request == 1 else { throw URLError(.notConnectedToInternet) }
    let chunks = AsyncThrowingStream<ArraySlice<UInt8>, any Error> { [bodyReads] in
      bodyReads.withValue { $0 += 1 }
      try? await Task.sleep(for: .seconds(60))
      throw URLError(.cancelled)
    }
    return (
      HTTPResponse(status: .ok), HTTPBody(chunks, length: .unknown, iterationBehavior: .single)
    )
  }
}
