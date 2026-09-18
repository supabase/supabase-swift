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

@testable import Auth

// `withMainSerialExecutor` mutates a process-global flag (ConcurrencyExtras'
// `uncheckedUseMainSerialExecutor`) to force deterministic task scheduling within its closure.
// Swift Testing runs tests in the same suite concurrently by default, so two tests racing to
// flip that global would interfere with each other — serialize this suite, mirroring the
// `_clock`-swap precedent in PostgrestBuilderTests (PR #1095). `.mainSerialExecutorSerialized`
// additionally prevents this suite from interleaving with any other suite (in this or another
// target) that also calls `withMainSerialExecutor`, since `.serialized` alone only serializes a
// suite's own tests.
@Suite(.serialized, .mainSerialExecutorSerialized)
struct SessionManagerTests {
  let http = RecordingTransport()
  // Unique negative clientID so this suite's process-global `Dependencies` entry can't be
  // clobbered by another suite running concurrently (Swift Testing runs suites in parallel;
  // `AuthClientID` is an `Int` and `AuthClient`'s own generator only ever hands out positive ids,
  // so negatives are collision-free).
  let clientID: AuthClientID = -1

  var sut: SessionManager {
    Dependencies[clientID].sessionManager
  }

  init() {
    Dependencies[clientID] = .init(
      configuration: .init(
        url: clientURL,
        localStorage: InMemoryLocalStorage(),
        automaticallyRefreshesToken: false
      ),
      http: HTTPClient(transport: http),
      api: APIClient(clientID: clientID),
      codeVerifierStorage: .mock,
      sessionStorage: SessionStorage.live(clientID: clientID),
      sessionManager: SessionManager.live(clientID: clientID),
      logger: supabaseDefaultLogger(label: "io.supabase.auth")
    )
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
  func cancellationFromTransportIsNotWrapped() async {
    http.respond { _, _ in throw CancellationError() }
    Dependencies[clientID].sessionStorage.store(.expired)

    await #expect(throws: CancellationError.self) {
      _ = try await sut.session()
    }
  }

  @Test
  func customFetchErrorIsNotWrapped() async {
    struct FetchError: Error {}
    http.respond { _, _ in throw FetchError() }
    Dependencies[clientID].sessionStorage.store(.expired)

    await #expect(throws: FetchError.self) {
      _ = try await sut.session()
    }
  }

  @Test
  func session_shouldReturnValidSession() async throws {
    try await withMainSerialExecutor {
      let session = Session.valid
      Dependencies[clientID].sessionStorage.store(session)

      let returnedSession = try await sut.session()
      expectNoDifference(returnedSession, session)
    }
  }

  @Test
  func session_shouldRefreshSession_whenCurrentSessionExpired() async throws {
    try await withMainSerialExecutor {
      let currentSession = Session.expired
      Dependencies[clientID].sessionStorage.store(currentSession)

      let validSession = Session.valid

      let refreshSessionCallCount = LockIsolated(0)

      let (refreshSessionStream, refreshSessionContinuation) = AsyncStream<Session>.makeStream()

      http.respond(when: { $0.url?.path.contains("/token") == true }) { _, _ in
        refreshSessionCallCount.withValue { $0 += 1 }
        let session = await refreshSessionStream.first(where: { _ in true })!
        return (HTTPResponse(status: .ok), try AuthClient.Configuration.jsonEncoder.encode(session))
      }

      // Fire N tasks and call sut.session()
      let tasks = (0..<10).map { _ in
        Task {
          try await sut.session()
        }
      }

      await Task.yield()

      refreshSessionContinuation.yield(validSession)
      refreshSessionContinuation.finish()

      // Await for all tasks to complete.
      var result: [Result<Session, any Error>] = []
      for task in tasks {
        let value = await task.result
        result.append(value)
      }

      // Verify that refresher and storage was called only once.
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
    Dependencies[clientID] = .init(
      configuration: .init(
        url: clientURL,
        localStorage: InMemoryLocalStorage(),
        automaticallyRefreshesToken: false,
        clock: clock
      ),
      http: HTTPClient(transport: http),
      api: APIClient(clientID: clientID),
      codeVerifierStorage: .mock,
      sessionStorage: SessionStorage.live(clientID: clientID),
      sessionManager: SessionManager.live(clientID: clientID),
      logger: supabaseDefaultLogger(label: "io.supabase.auth")
    )

    // `.expired` is close enough to expiry that every tick refreshes, and the
    // response is expired too, so the next tick refreshes again.
    Dependencies[clientID].sessionStorage.store(.expired)

    let refreshCount = LockIsolated(0)
    http.respond(when: { $0.url?.path.contains("/token") == true }) { _, _ in
      refreshCount.withValue { $0 += 1 }
      return (
        HTTPResponse(status: .ok),
        try AuthClient.Configuration.jsonEncoder.encode(Session.expired)
      )
    }

    await sut.startAutoRefresh()

    // The loop refreshes once before its first sleep.
    let sawFirstTick = await waitUntil { refreshCount.value >= 1 }

    // Only advancing the injected clock releases the next tick — no wall-clock
    // time passes. Advance in a loop so the test does not depend on the
    // auto-refresh task having reached its `sleep` at any exact moment.
    for _ in 0..<50 where refreshCount.value < 2 {
      await clock.advance(by: .seconds(autoRefreshTickDuration))
      try? await Task.sleep(nanoseconds: 10_000_000)
    }
    let tickCount = refreshCount.value

    // Awaited, not deferred into a fire-and-forget Task: `LiveSessionManager` resolves
    // `Dependencies[clientID]` on every access, so a loop still running when this test returns
    // starts refreshing against the *next* test's transport and storage.
    await sut.stopAutoRefresh()

    #expect(sawFirstTick)
    #expect(tickCount >= 2)
  }

  // MARK: - Commit guard (SDK-1882)

  /// A session with tokens derived from `name`, so two sessions in one test are distinguishable.
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

  /// Holds the `/token` response until `release()` is called, so a sign-out can interleave.
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
    let token = Dependencies[clientID].eventEmitter.attach { event, _ in
      events.withValue { $0.append(event) }
    }
    return (events, { token.cancel() })
  }

  @Test
  func staleRefreshDoesNotOverwriteANewerStoredSession() async throws {
    let userA = session("A")
    let userB = session("B")
    let refreshedA = session("A2")

    Dependencies[clientID].sessionStorage.store(userA)
    let (requestSeen, release) = heldTokenResponse {
      (HTTPResponse(status: .ok), try AuthClient.Configuration.jsonEncoder.encode(refreshedA))
    }
    let (events, stopCollecting) = collectAuthEvents()
    defer { stopCollecting() }

    let refresh = Task { try await sut.refreshSession(userA.refreshToken) }
    let sawRequest = await waitUntil { requestSeen.value }
    #expect(sawRequest)

    // User A signs out, then user B signs in — both land while A's refresh is in flight.
    await sut.remove()
    await sut.update(userB)

    release()
    let result = await refresh.result

    expectNoDifference(
      Dependencies[clientID].sessionStorage.get()?.refreshToken, userB.refreshToken)
    #expect(!events.value.contains(.tokenRefreshed))
    #expect((result.error as? AuthError)?.kind == .refreshDiscarded)
  }

  @Test
  func staleRefreshDoesNotDeleteANewerStoredSessionOnACleanupError() async throws {
    let userA = session("A")
    let userB = session("B")

    Dependencies[clientID].sessionStorage.store(userA)
    // `/logout` has already revoked A's refresh token by the time this answer arrives.
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

    await sut.remove()
    await sut.update(userB)

    release()
    let result = await refresh.result

    expectNoDifference(
      Dependencies[clientID].sessionStorage.get()?.refreshToken, userB.refreshToken)
    #expect(!events.value.contains(.signedOut))
    // A's caller still learns its own session is gone — the server did reject A's refresh token.
    // What must not happen is B being signed out along with it.
    #expect((result.error as? AuthError)?.kind == .sessionMissing)
  }

  @Test
  func refreshForADifferentTokenDoesNotJoinAnInFlightRefresh() async throws {
    let userA = session("A")
    let userB = session("B")
    let refreshedA = session("A2")
    let refreshedB = session("B2")

    Dependencies[clientID].sessionStorage.store(userA)

    let tokensRequested = LockIsolated<[String]>([])
    let (gate, continuation) = AsyncStream<Void>.makeStream()

    struct RefreshBody: Decodable { let refreshToken: String }

    // Answers each token with its own rotated session, so joining the wrong task is visible in
    // the result and not only in the request count.
    http.respond(when: { $0.url?.path.contains("/token") == true }) { _, body in
      let refreshToken = try AuthClient.Configuration.jsonDecoder.decode(
        RefreshBody.self, from: body ?? Data()
      ).refreshToken
      tokensRequested.withValue { $0.append(refreshToken) }

      // Hold A's request only, so B's refresh is requested while A's is still in flight.
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

    await sut.update(userB)
    // Started as a task, not awaited inline: while the bug is present B joins A's gated task, and
    // awaiting inline would deadlock against the release below instead of failing.
    let refreshB = Task { try await sut.refreshSession(userB.refreshToken) }
    _ = await waitUntil { tokensRequested.value.count == 2 }

    continuation.yield(())
    continuation.finish()
    _ = await refreshA.result
    let resultB = await refreshB.result

    // B asked to refresh its own token, so it must not be served A's in-flight task.
    expectNoDifference(try resultB.get().refreshToken, refreshedB.refreshToken)
    expectNoDifference(tokensRequested.value.sorted(), [userA, userB].map(\.refreshToken).sorted())
  }

  @Test
  func refreshCommitsWhenStorageStartsEmpty() async throws {
    // `setSession(accessToken:refreshToken:)` refreshes an externally-sourced token with nothing
    // stored yet. The guard must not mistake that for a session replaced under it.
    let hydrated = session("hydrated")

    http.respond(when: { $0.url?.path.contains("/token") == true }) { _, _ in
      (HTTPResponse(status: .ok), try AuthClient.Configuration.jsonEncoder.encode(hydrated))
    }

    let result = try await sut.refreshSession("externally-sourced-refresh")

    expectNoDifference(result.refreshToken, hydrated.refreshToken)
    expectNoDifference(
      Dependencies[clientID].sessionStorage.get()?.refreshToken, hydrated.refreshToken)
  }
}
