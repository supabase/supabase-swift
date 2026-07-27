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
import TestHelpers
import Testing

@testable import Auth

// `withMainSerialExecutor` mutates a process-global flag (ConcurrencyExtras'
// `uncheckedUseMainSerialExecutor`) to force deterministic task scheduling within its closure.
// Swift Testing runs tests in the same suite concurrently by default, so two tests racing to
// flip that global would interfere with each other — serialize this suite, mirroring the
// `_clock`-swap precedent in PostgrestBuilderTests (PR #1095).
@Suite(.serialized)
struct SessionManagerTests {
  let http = HTTPClientMock()
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
        autoRefreshToken: false
      ),
      http: http,
      api: APIClient(clientID: clientID),
      codeVerifierStorage: .mock,
      sessionStorage: SessionStorage.live(clientID: clientID),
      sessionManager: SessionManager.live(clientID: clientID)
    )
  }

  @Test
  func session_shouldFailWithSessionNotFound() async {
    await withMainSerialExecutor {
      do {
        _ = try await sut.session()
        Issue.record("Expected a \(AuthError.sessionMissing) failure")
      } catch {
        assertInlineSnapshot(of: error, as: .dump) {
          """
          - AuthError.sessionMissing

          """
        }
      }
    }
  }

  @Test
  func session_shouldReturnValidSession() async throws {
    try await withMainSerialExecutor {
      let session = Session.validSession
      Dependencies[clientID].sessionStorage.store(session)

      let returnedSession = try await sut.session()
      expectNoDifference(returnedSession, session)
    }
  }

  @Test
  func session_shouldRefreshSession_whenCurrentSessionExpired() async throws {
    try await withMainSerialExecutor {
      let currentSession = Session.expiredSession
      Dependencies[clientID].sessionStorage.store(currentSession)

      let validSession = Session.validSession

      let refreshSessionCallCount = LockIsolated(0)

      let (refreshSessionStream, refreshSessionContinuation) = AsyncStream<Session>.makeStream()

      await http.when(
        { $0.url.path.contains("/token") },
        return: { _ in
          refreshSessionCallCount.withValue { $0 += 1 }
          let session = await refreshSessionStream.first(where: { _ in true })!
          return .stub(session)
        }
      )

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
}
