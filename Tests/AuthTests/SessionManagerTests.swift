//
//  SessionManagerTests.swift
//
//
//  Created by Guilherme Souza on 23/10/23.
//

import Clocks
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
    clock: any Clock<Duration> = ContinuousClock(),
    date: @escaping @Sendable () -> Date = { Date() }
  ) -> Dependencies {
    .live(
      configuration: .init(
        url: clientURL,
        storageKey: uniqueStorageKey(),
        localStorage: InMemoryLocalStorage(),
        automaticallyRefreshesToken: false,
        clock: clock
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

  @Test
  func autoRefreshTicksOnTheInjectedClock() async throws {
    let clock = TestClock()
    let dependencies = Self.makeDependencies(http: http, clock: clock)
    let sut = dependencies.sessionManager

    try await dependencies.seedSession(.expired)

    let refreshCount = LockIsolated(0)
    http.respond(when: { $0.url?.path.contains("/token") == true }) { _, _ in
      refreshCount.withValue { $0 += 1 }
      return (
        HTTPResponse(status: .ok),
        try AuthClient.Configuration.jsonEncoder.encode(Session.expired)
      )
    }

    await sut.startAutoRefresh()

    let sawFirstTick = await waitUntil { refreshCount.value >= 1 }

    for _ in 0..<50 where refreshCount.value < 2 {
      await clock.advance(by: .seconds(autoRefreshTickDuration))
      try? await Task.sleep(nanoseconds: 10_000_000)
    }
    let tickCount = refreshCount.value

    await sut.stopAutoRefresh()

    #expect(sawFirstTick)
    #expect(tickCount >= 2)
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

  private func collectAuthEvents() -> (events: LockIsolated<[AuthChangeEvent]>, stop: () -> Void) {
    let events = LockIsolated<[AuthChangeEvent]>([])
    let changes = dependencies.sessionStore.changes()
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
    let userA = session("A")
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
